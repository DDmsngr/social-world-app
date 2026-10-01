-- Чаты: ответы и пересылки, «отправить без звука», отложенные сообщения.
--
-- Накатывать после 0033. Расширение pg_cron нужно для отправки отложенных
-- (в Supabase оно включается в Database → Extensions); без него миграция
-- проходит, но отложенные сами не уходят — см. раздел 5.
--
--  1. meta — цитата и «переслано от». В группах лежит открытой колонкой, в
--     личных диалогах внутри шифротекста (колонка там пустая: см. check).
--     silent — флаг «без звука»: открытый, по нему push-send выбирает тихий
--     канал. Это настройка доставки, а не содержимое.
--  2. Надгробие удалённого сообщения (0033) стирает и meta.
--  3. user_presence — «когда человек в последний раз был в приложении».
--     Читает только сервер: ни клиент, ни другие люди эту таблицу не видят.
--  4. chat_scheduled_messages — отложенные тексты. Личные лежат уже
--     зашифрованными для собеседника (шифрование не зависит от времени
--     отправки), поэтому сервер выпускает их, ничего не расшифровывая.
--  5. release_scheduled_chat_messages() раз в минуту переносит созданное в
--     chat_messages: по времени или когда собеседник появился в сети.

-- ── 1. сообщения ────────────────────────────────────────────────────────────

alter table chat_messages
  add column meta   jsonb check (meta is null or pg_column_size(meta) <= 2048),
  add column silent boolean not null default false;

alter table chat_messages
  add constraint chat_messages_meta_open check (meta is null or ciphertext is null);

-- ── 2. удаление стирает и meta ──────────────────────────────────────────────

create or replace function delete_chat_messages(in_ids uuid[])
returns setof uuid
language sql security definer set search_path = public as $$
  update chat_messages m
     set deleted_at = now(),
         body = null, media = null, meta = null,
         ciphertext = null, nonce = null, mac = null, signature = null
   where m.id = any(in_ids)
     and m.deleted_at is null
     and (
       m.sender_id = auth.uid()
       or exists (
         select 1
         from chat_members me
         join chat_conversations c on c.id = me.conversation_id
         where me.conversation_id = m.conversation_id
           and me.profile_id = auth.uid()
           and me.role = 'owner'
           and c.direct_key is null
       )
     )
  returning m.id;
$$;

-- ── 3. присутствие ──────────────────────────────────────────────────────────

create table user_presence (
  profile_id uuid primary key references profiles on delete cascade,
  seen_at    timestamptz not null default now()
);

-- Политик нет и прав нет: таблицу читает и пишет только security definer.
alter table user_presence enable row level security;
revoke all on user_presence from public, anon, authenticated;

create function touch_last_seen() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  insert into user_presence (profile_id, seen_at) values (auth.uid(), now())
  on conflict (profile_id) do update set seen_at = excluded.seen_at;
end;
$$;

revoke all on function touch_last_seen from public;
grant execute on function touch_last_seen to authenticated;

-- «Собеседник в сети»: был в приложении не больше двух минут назад. Наружу не
-- отдаётся — только release_scheduled_chat_messages.
create function chat_peer_online(in_conversation uuid, in_sender uuid)
returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select exists (
    select 1
    from chat_members m
    join user_presence p on p.profile_id = m.profile_id
    where m.conversation_id = in_conversation
      and m.profile_id <> in_sender
      and p.seen_at > now() - interval '2 minutes'
  );
$$;

revoke all on function chat_peer_online from public;

-- ── 4. отложенные сообщения ─────────────────────────────────────────────────

create table chat_scheduled_messages (
  id               uuid primary key,
  conversation_id  uuid not null references chat_conversations on delete cascade,
  sender_id        uuid not null references profiles on delete cascade,
  kind             text not null default 'text' check (kind = 'text'),
  body             text check (body is null or char_length(body) between 1 and 4000),
  meta             jsonb check (meta is null or pg_column_size(meta) <= 2048),
  ciphertext       text check (ciphertext is null or length(ciphertext) <= 65536),
  nonce            text check (nonce is null or length(nonce) <= 64),
  mac              text check (mac is null or length(mac) <= 64),
  signature        text check (signature is null or length(signature) <= 256),
  protocol_version smallint not null default 1 check (protocol_version > 0),
  silent           boolean not null default false,
  send_at          timestamptz,
  when_online      boolean not null default false,
  created_at       timestamptz not null default now(),
  -- Ровно один способ: к времени или к появлению собеседника в сети.
  constraint chat_scheduled_mode check ((send_at is not null) <> when_online),
  -- Как у chat_messages: группа — открытый текст, личный — шифротекст.
  constraint chat_scheduled_payload check (
    (body is not null and ciphertext is null and nonce is null and mac is null and signature is null)
    or
    (body is null and meta is null
      and ciphertext is not null and nonce is not null and mac is not null and signature is not null)
  )
);

create index chat_scheduled_due_idx on chat_scheduled_messages (send_at)
  where send_at is not null;
create index chat_scheduled_online_idx on chat_scheduled_messages (conversation_id)
  where when_online;
create index chat_scheduled_sender_idx on chat_scheduled_messages (sender_id, conversation_id);

alter table chat_scheduled_messages enable row level security;
revoke all on chat_scheduled_messages from public, anon, authenticated;
grant select, insert, delete on chat_scheduled_messages to authenticated;

create policy chat_scheduled_select on chat_scheduled_messages
  for select to authenticated using (sender_id = auth.uid());

create policy chat_scheduled_delete on chat_scheduled_messages
  for delete to authenticated using (sender_id = auth.uid());

create policy chat_scheduled_insert on chat_scheduled_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and is_chat_member(conversation_id)
    and coalesce(chat_can_post(conversation_id, ciphertext is null), false)
  );

-- Не больше 50 отложенных на человека и не дальше года вперёд.
create function chat_scheduled_limits() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from chat_scheduled_messages
       where sender_id = new.sender_id) >= 50 then
    raise exception 'rate_limit: слишком много отложенных сообщений'
      using errcode = 'P0001', hint = 'chat_scheduled_messages';
  end if;
  if new.send_at is not null and new.send_at > now() + interval '366 days' then
    raise exception 'send_at слишком далеко' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger chat_scheduled_limits before insert on chat_scheduled_messages
  for each row execute function chat_scheduled_limits();

revoke all on function chat_scheduled_limits from public;

-- ── 5. выпуск отложенных ────────────────────────────────────────────────────

-- Вызывается раз в минуту. Правила отправки проверяются заново: чат мог
-- закрыться, участника — заблокировать. Нарушившее правила тихо удаляется,
-- упавшее на антиспаме (rate_limit) остаётся до следующего прохода.
create function release_scheduled_chat_messages() returns integer
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  r        chat_scheduled_messages;
  released integer := 0;
begin
  -- «Когда будет в сети» не вечное: через две недели собеседник, видимо, не
  -- появится, и сообщение уже не к месту.
  delete from chat_scheduled_messages
   where when_online and created_at < now() - interval '14 days';

  for r in
    select s.*
    from chat_scheduled_messages s
    where (s.send_at is not null and s.send_at <= now())
       or (s.when_online and chat_peer_online(s.conversation_id, s.sender_id))
    order by coalesce(s.send_at, s.created_at)
    limit 200
    for update skip locked
  loop
    begin
      if exists (
        select 1
        from chat_conversations c
        join chat_members me
          on me.conversation_id = c.id and me.profile_id = r.sender_id
        where c.id = r.conversation_id
          and c.closed_at is null
          and (
            c.direct_key is null
            or not exists (
              select 1 from chat_members m
              where m.conversation_id = c.id
                and m.profile_id <> r.sender_id
                and chat_is_blocked_pair(r.sender_id, m.profile_id)
            )
          )
      ) then
        insert into chat_messages (
          id, conversation_id, sender_id, kind, body, meta,
          ciphertext, nonce, mac, signature, protocol_version, silent
        ) values (
          r.id, r.conversation_id, r.sender_id, r.kind, r.body, r.meta,
          r.ciphertext, r.nonce, r.mac, r.signature, r.protocol_version, r.silent
        );
        released := released + 1;
      end if;
      delete from chat_scheduled_messages where id = r.id;
    exception when others then
      raise warning 'отложенное % не ушло: %', r.id, sqlerrm;
    end;
  end loop;
  return released;
end;
$$;

revoke all on function release_scheduled_chat_messages from public;

-- Раз в минуту. pg_cron в Supabase включается в Database → Extensions; если
-- его нет, расписание не создаётся, а миграция всё равно проходит.
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron недоступен (%): включите его и повторите блок ниже', sqlerrm;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'release-scheduled-chat-messages';
    perform cron.schedule(
      'release-scheduled-chat-messages',
      '* * * * *',
      'select release_scheduled_chat_messages()'
    );
  else
    raise notice 'Отложенные сообщения не будут уходить, пока не настроен pg_cron: '
      'select cron.schedule(''release-scheduled-chat-messages'', ''* * * * *'', '
      '''select release_scheduled_chat_messages()'');';
  end if;
end $$;
