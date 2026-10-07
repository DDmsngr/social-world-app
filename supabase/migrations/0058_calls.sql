-- Голосовые и видеозвонки в личных чатах (WebRTC).
--
-- Сервер хранит только факт звонка и его состояние: кто, кому, когда, чем
-- кончился. Сам звук и видео идут напрямую между телефонами (или через свой
-- TURN на ВМ, если напрямую не пробиться), шифруются DTLS-SRTP. Сигналы
-- WebRTC (offer/answer/кандидаты) ходят через Realtime broadcast по каналу
-- `call:<id>` и в базе не лежат.
--
-- Входящий звонок будит телефон data-пушем (push-send, тип 'call'), смена
-- состояния — пушем 'call_update': он гасит звонилку на других телефонах
-- человека и превращается в «пропущенный», если не ответили.
--
-- Секрет TURN — в Vault (не в этом файле), заводится один раз:
--   select vault.create_secret('<случайная строка>', 'turn_secret');
-- тот же секрет стоит в /etc/turnserver.conf на ВМ (static-auth-secret).

create table calls (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references chat_conversations(id) on delete cascade,
  caller_id       uuid not null references profiles(id) on delete cascade,
  callee_id       uuid not null references profiles(id) on delete cascade,
  video           boolean not null default false,
  -- ringing → active → ended; из ringing: declined (сбросил), cancelled
  -- (звонящий передумал), missed (никто не ответил), busy (занято).
  status          text not null default 'ringing'
                  check (status in ('ringing', 'active', 'ended', 'declined', 'cancelled', 'missed', 'busy')),
  created_at      timestamptz not null default now(),
  answered_at     timestamptz,
  ended_at        timestamptz,
  ended_by        uuid references profiles(id) on delete set null
);

create index calls_callee_idx on calls (callee_id, created_at desc);
create index calls_caller_idx on calls (caller_id, created_at desc);
create index calls_conversation_idx on calls (conversation_id, created_at desc);

alter table calls enable row level security;

-- Читать свои звонки (и получать их изменения через Realtime) — только
-- участникам. Пишут только функции ниже.
create policy calls_select on calls for select to authenticated
  using (auth.uid() in (caller_id, callee_id));

grant select on calls to authenticated;

alter publication supabase_realtime add table calls;

-- Звонок, который «висит» дольше разумного, считается завершённым: телефон мог
-- умереть посреди разговора, и человек не должен навсегда остаться «занят».
create function calls_expire_stale() returns void
language sql security definer set search_path = public as $$
  update calls set status = 'missed', ended_at = now()
  where status = 'ringing' and created_at < now() - interval '70 seconds';
  update calls set status = 'ended', ended_at = now()
  where status = 'active' and answered_at < now() - interval '6 hours';
$$;
revoke all on function calls_expire_stale() from public, anon, authenticated;

-- ── позвонить ───────────────────────────────────────────────────────────────

create function start_call(in_conversation uuid, in_video boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  peer uuid;
  call_id uuid;
  is_busy boolean;
begin
  if me is null then raise exception 'нужен вход'; end if;

  if not exists (
    select 1 from chat_conversations
    where id = in_conversation and direct_key is not null
  ) then
    raise exception 'звонить можно только в личном чате';
  end if;
  if not exists (
    select 1 from chat_members where conversation_id = in_conversation and profile_id = me
  ) then
    raise exception 'вы не участник этого чата';
  end if;

  select profile_id into peer from chat_members
  where conversation_id = in_conversation and profile_id <> me
  limit 1;
  if peer is null then raise exception 'собеседник не найден'; end if;

  if exists (
    select 1 from user_blocks
    where (blocker_id = peer and blocked_id = me) or (blocker_id = me and blocked_id = peer)
  ) then
    raise exception 'звонок недоступен';
  end if;

  -- Защита от «звонилки» по кругу.
  if (select count(*) from calls where caller_id = me and created_at > now() - interval '10 minutes') >= 20 then
    raise exception 'слишком много звонков, попробуйте позже';
  end if;

  perform calls_expire_stale();

  select exists (
    select 1 from calls
    where status in ('ringing', 'active')
      and (peer in (caller_id, callee_id) or me in (caller_id, callee_id))
  ) into is_busy;

  insert into calls (conversation_id, caller_id, callee_id, video, status, ended_at)
  values (in_conversation, me, peer, coalesce(in_video, false),
          case when is_busy then 'busy' else 'ringing' end,
          case when is_busy then now() end)
  returning id into call_id;

  if not is_busy then
    perform push_dispatch(jsonb_build_object('type', 'call', 'call_id', call_id));
  end if;

  return jsonb_build_object(
    'id', call_id,
    'status', case when is_busy then 'busy' else 'ringing' end,
    'peer_id', peer
  );
end $$;

-- ── ответить ────────────────────────────────────────────────────────────────

create function answer_call(in_call uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  answered boolean;
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;

  update calls set status = 'active', answered_at = now()
  where id = in_call
    and callee_id = auth.uid()
    and status = 'ringing'
    and created_at > now() - interval '70 seconds'
  returning true into answered;

  if coalesce(answered, false) then
    -- Остальные телефоны того же человека перестают звонить.
    perform push_dispatch(jsonb_build_object('type', 'call_update', 'call_id', in_call));
  end if;
  return coalesce(answered, false);
end $$;

-- ── завершить ───────────────────────────────────────────────────────────────
-- in_reason: 'timeout' — звонящий не дождался ответа. Остальное решает
-- состояние: в ringing сбросивший получатель — declined, звонящий —
-- cancelled; в active — ended.

create function end_call(in_call uuid, in_reason text default null) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c calls;
  next_status text;
begin
  if me is null then raise exception 'нужен вход'; end if;

  select * into c from calls where id = in_call for update;
  if c.id is null or me not in (c.caller_id, c.callee_id) then
    raise exception 'звонок не найден';
  end if;
  if c.status not in ('ringing', 'active') then return c.status; end if;

  next_status := case
    when c.status = 'active' then 'ended'
    when me = c.callee_id then 'declined'
    when in_reason = 'timeout' then 'missed'
    else 'cancelled'
  end;

  update calls set status = next_status, ended_at = now(), ended_by = me
  where id = in_call;

  -- Получатель узнаёт об этом и при закрытом приложении: звонилка гаснет,
  -- непринятый звонок становится «пропущенным».
  if c.status = 'ringing' then
    perform push_dispatch(jsonb_build_object('type', 'call_update', 'call_id', in_call));
  end if;
  return next_status;
end $$;

-- ── ключ к TURN ─────────────────────────────────────────────────────────────
-- Временный логин по схеме coturn use-auth-secret: имя «срок:кто», пароль —
-- HMAC-SHA1 от имени на общем секрете. Живёт сутки; секрет наружу не уходит.

create function turn_credentials() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  secret text;
  username text;
  host constant text := 'api-socialworld.deepdrift.tech';
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'turn_secret';

  if secret is null then
    return jsonb_build_object('iceServers', jsonb_build_array(
      jsonb_build_object('urls', 'stun:' || host || ':3478')
    ));
  end if;

  username := (extract(epoch from now())::bigint + 86400)::text || ':' || auth.uid()::text;
  return jsonb_build_object(
    'ttl', 86400,
    'iceServers', jsonb_build_array(
      jsonb_build_object('urls', 'stun:' || host || ':3478'),
      jsonb_build_object(
        'urls', jsonb_build_array(
          'turn:' || host || ':3478?transport=udp',
          'turn:' || host || ':3478?transport=tcp'
        ),
        'username', username,
        'credential', encode(hmac(username, secret, 'sha1'), 'base64')
      )
    )
  );
end $$;

revoke all on function start_call(uuid, boolean), answer_call(uuid), end_call(uuid, text), turn_credentials()
  from public, anon;
grant execute on function start_call(uuid, boolean), answer_call(uuid), end_call(uuid, text), turn_credentials()
  to authenticated;
