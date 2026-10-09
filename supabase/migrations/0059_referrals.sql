-- Реферальная программа (ТЗ раздел 8, docs/referral-activity-points.md).
--
-- Персональный код у каждого (profiles.referral_code) → ссылка …/r/<код> и QR.
-- Новый человек после регистрации «заявляет» пригласившего (claim_referral):
-- по ссылке, из буфера обмена при первом запуске или вручную. Пригласивший
-- один и навсегда.
--
-- Баллы (Activity Points) — это social_score, «карма» как на Reddit: тратить
-- их не на что, они показывают вклад человека. Журнал реферальных начислений —
-- point_transactions со статусами; в карму (score_events → social_score) идёт
-- только подтверждённое.
--
-- Жизненный цикл (раз в минуту, referrals_tick):
--   waiting   — заявлен, ждёт активации (профиль + первое действие);
--   activated — выполнил условия: пяти уровням вверх начисляется pending
--               (100/50/25/15/10), через hold_minutes — проверка: всё ещё
--               в порядке → confirmed и в карму, нет → cancelled с обратной
--               операцией и уведомлением;
--   expired   — не активировался за activation_days;
--   suspicious— антифрод набрал fraud_threshold: начислений нет до ручного
--               решения (referral_review);
-- Уже подтверждённое при выявленной накрутке снимается referral_reverse —
-- отдельной операцией reversed, исходная остаётся в истории.
--
-- Антифрод собирает отпечаток устройства (хеш Android ID) и IP — это
-- персональные данные, сбор должен быть описан в пользовательском соглашении.

-- ── настройки ────────────────────────────────────────────────────────────────

create table referral_settings (
  id                     boolean primary key default true check (id),
  enabled                boolean not null default true,
  level_points           integer[] not null default '{100,50,25,15,10}',
  max_points_per_invitee integer not null default 200,
  hold_minutes           integer not null default 10,      -- на бою 1440 (24 ч)
  activation_days        integer not null default 14,
  claim_days             integer not null default 7,       -- сколько дней после регистрации можно указать пригласившего
  daily_invite_limit     integer not null default 30,
  require_avatar         boolean not null default true,
  require_first_action   boolean not null default true,
  require_phone          boolean not null default false,   -- телефона пока нет (VK ID ждёт решения)
  fraud_threshold        integer not null default 50,
  updated_at             timestamptz not null default now()
);
insert into referral_settings default values;
alter table referral_settings enable row level security;

-- ── код и связи ─────────────────────────────────────────────────────────────

alter table profiles add column referral_code text unique
  check (referral_code is null or referral_code ~ '^[A-Z2-9]{6,10}$');

create table referrals (
  invitee_id    uuid primary key references profiles(id) on delete cascade,
  inviter_id    uuid not null references profiles(id) on delete cascade,
  code          text not null,
  source        text not null default 'link' check (source in ('link', 'clipboard', 'manual')),
  status        text not null default 'waiting'
                check (status in ('waiting', 'activated', 'expired', 'suspicious', 'rejected')),
  fraud_score   integer not null default 0,
  fraud_reasons text[] not null default '{}',
  device_hash   text,
  ip            text,
  created_at    timestamptz not null default now(),
  activated_at  timestamptz,
  reviewed_at   timestamptz,
  check (inviter_id <> invitee_id)
);
create index referrals_inviter_idx on referrals (inviter_id, created_at desc);
alter table referrals enable row level security;

-- Где и под каким аккаунтом видели устройство. Без внешнего ключа намеренно:
-- запись остаётся и после удаления аккаунта — так видно повторную регистрацию
-- с того же телефона.
create table device_sightings (
  device_hash text not null,
  profile_id  uuid not null,
  ip          text,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  primary key (device_hash, profile_id)
);
create index device_sightings_profile_idx on device_sightings (profile_id);
alter table device_sightings enable row level security;

-- ── журнал баллов ───────────────────────────────────────────────────────────

create table point_transactions (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references profiles(id) on delete cascade,
  amount        integer not null,
  -- referral_level_<n> — начисление; referral_activation_expired — отмена
  -- не подтвердившегося; referral_fraud_reversal — снятие подтверждённого.
  code          text not null,
  status        text not null check (status in ('pending', 'confirmed', 'cancelled', 'reversed')),
  level         smallint,
  invitee_id    uuid references profiles(id) on delete set null,
  source_id     uuid references point_transactions(id) on delete set null,
  reason        text,
  confirm_after timestamptz,
  settled_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index point_transactions_profile_idx on point_transactions (profile_id, created_at desc);
create index point_transactions_pending_idx on point_transactions (confirm_after) where status = 'pending';
alter table point_transactions enable row level security;
create policy point_transactions_own on point_transactions for select to authenticated
  using (profile_id = auth.uid());
grant select on point_transactions to authenticated;

-- ── аналитика ───────────────────────────────────────────────────────────────
-- События воронки пишет сервер (источник правды для начислений). Продуктовая
-- аналитика экранов — отдельно (AppMetrica), сюда только бизнес-события.

create table analytics_events (
  id         bigserial primary key,
  profile_id uuid,
  name       text not null check (char_length(name) <= 64),
  props      jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index analytics_events_name_idx on analytics_events (name, created_at desc);
alter table analytics_events enable row level security;

create function track_event(in_name text, in_props jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  -- Клиент пишет только события воронки и не чаще разумного.
  if in_name !~ '^(referral|activity_points)_[a-z_]{1,40}$' then return; end if;
  if (select count(*) from analytics_events
      where profile_id = auth.uid() and created_at > now() - interval '1 minute') >= 30 then
    return;
  end if;
  insert into analytics_events (profile_id, name, props)
  values (auth.uid(), in_name, coalesce(in_props, '{}'));
end $$;

create function referral_log(in_profile uuid, in_name text, in_props jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into analytics_events (profile_id, name, props) values (in_profile, in_name, coalesce(in_props, '{}'));
$$;

-- ── вспомогательное ─────────────────────────────────────────────────────────

create function referral_new_code() returns text
language plpgsql set search_path = public, extensions as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
begin
  loop
    candidate := '';
    for i in 1..6 loop
      candidate := candidate || substr(alphabet, 1 + (get_byte(gen_random_bytes(1), 0) % 32), 1);
    end loop;
    exit when not exists (select 1 from profiles where referral_code = candidate);
  end loop;
  return candidate;
end $$;

create function referral_ensure_code(in_profile uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  existing text;
begin
  select referral_code into existing from profiles where id = in_profile;
  if existing is not null then return existing; end if;
  update profiles set referral_code = referral_new_code()
  where id = in_profile and referral_code is null
  returning referral_code into existing;
  return coalesce(existing, (select referral_code from profiles where id = in_profile));
end $$;

-- Первый адрес из X-Forwarded-For (телефон → Caddy → облако).
create function request_ip() returns text
language sql stable as $$
  select nullif(trim(split_part(
    coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1)), '');
$$;

-- Цепочка вверх: уровень 1 — тот, кто пригласил этого человека.
create function referral_ancestors(in_profile uuid, in_depth integer)
returns table (level integer, profile_id uuid)
language sql stable security definer set search_path = public as $$
  with recursive up(level, profile_id) as (
    select 1, r.inviter_id from referrals r
    where r.invitee_id = in_profile and r.status <> 'rejected'
    union all
    select up.level + 1, r.inviter_id
    from up join referrals r on r.invitee_id = up.profile_id
    where up.level < in_depth and r.status <> 'rejected'
  )
  select level, profile_id from up;
$$;

create function referral_activation_ok(in_profile uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  s referral_settings;
  p profiles;
begin
  select * into s from referral_settings;
  select * into p from profiles where id = in_profile;
  if p.id is null or p.status <> 'active' then return false; end if;
  if coalesce(trim(p.display_name), '') = '' then return false; end if;
  if s.require_avatar and p.avatar_url is null then return false; end if;
  if s.require_phone and not exists (
    select 1 from auth.users u where u.id = in_profile and u.phone is not null
  ) then return false; end if;
  if s.require_first_action and not (
    exists (select 1 from posts where author_id = in_profile)
    or exists (select 1 from chat_messages where sender_id = in_profile)
    or exists (select 1 from follows where follower_id = in_profile)
  ) then return false; end if;
  return true;
end $$;

-- ── клиент: устройство, мой код, заявить пригласившего ─────────────────────

create function report_device(in_device text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or in_device is null or in_device !~ '^[a-f0-9]{64}$' then return; end if;
  insert into device_sightings (device_hash, profile_id, ip)
  values (in_device, auth.uid(), request_ip())
  on conflict (device_hash, profile_id) do update
    set last_seen = now(), ip = coalesce(excluded.ip, device_sightings.ip);
end $$;

create function claim_referral(in_code text, in_device text default null, in_source text default 'link')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  s referral_settings;
  inviter uuid;
  normalized text := upper(regexp_replace(coalesce(in_code, ''), '[^A-Za-z0-9]', '', 'g'));
  client_ip text := request_ip();
  score integer := 0;
  reasons text[] := '{}';
  next_status text;
  my_created timestamptz;
begin
  if me is null then raise exception 'нужен вход'; end if;
  select * into s from referral_settings;
  if not s.enabled then raise exception 'программа приглашений сейчас выключена'; end if;
  if exists (select 1 from referrals where invitee_id = me) then
    raise exception 'пригласивший уже указан';
  end if;
  select created_at into my_created from profiles where id = me;
  if my_created < now() - make_interval(days => s.claim_days) then
    raise exception 'код приглашения можно указать только в первые % дн. после регистрации', s.claim_days;
  end if;

  select id into inviter from profiles where referral_code = normalized and status <> 'blocked';
  if inviter is null then raise exception 'код приглашения не найден'; end if;
  if inviter = me then raise exception 'нельзя пригласить самого себя'; end if;
  -- Искусственная петля: пригласивший сам оказался бы ниже меня.
  if exists (select 1 from referral_ancestors(inviter, 50) a where a.profile_id = me) then
    raise exception 'нельзя пригласить своего же приглашённого';
  end if;

  if in_device is not null and in_device ~ '^[a-f0-9]{64}$' then
    perform report_device(in_device);
    -- Тот же телефон, что у пригласившего, — свой второй аккаунт.
    if exists (select 1 from device_sightings where device_hash = in_device and profile_id = inviter) then
      perform referral_log(me, 'referral_fraud_detected', jsonb_build_object('reason', 'device_of_inviter', 'inviter', inviter));
      raise exception 'приглашение с этого устройства не засчитывается';
    end if;
    -- Телефон уже видел другие аккаунты (в том числе удалённые).
    if (select count(distinct profile_id) from device_sightings where device_hash = in_device and profile_id <> me) >= 2 then
      score := score + 40; reasons := reasons || 'shared_device';
    end if;
    if exists (
      select 1 from device_sightings d
      where d.device_hash = in_device and d.profile_id <> me
        and not exists (select 1 from profiles p where p.id = d.profile_id)
    ) then
      score := score + 50; reasons := reasons || 'device_of_deleted_account';
    end if;
  else
    score := score + 20; reasons := reasons || 'no_device';
  end if;

  if client_ip is not null then
    if exists (
      select 1 from device_sightings
      where profile_id = inviter and ip = client_ip and last_seen > now() - interval '30 days'
    ) then
      score := score + 30; reasons := reasons || 'same_ip_as_inviter';
    end if;
    if (select count(*) from referrals r
        where r.inviter_id = inviter and r.ip = client_ip and r.created_at > now() - interval '1 day') >= 2 then
      score := score + 40; reasons := reasons || 'ip_cluster';
    end if;
  end if;

  if (select count(*) from referrals where inviter_id = inviter and created_at > now() - interval '1 day')
      >= s.daily_invite_limit then
    raise exception 'у пригласившего закончился лимит приглашений на сегодня';
  end if;
  if (select count(*) from referrals where inviter_id = inviter and created_at > now() - interval '1 hour') >= 5 then
    score := score + 30; reasons := reasons || 'burst';
  end if;

  next_status := case when score >= s.fraud_threshold then 'suspicious' else 'waiting' end;
  insert into referrals (invitee_id, inviter_id, code, source, status, fraud_score, fraud_reasons, device_hash, ip)
  values (me, inviter, normalized,
          case when in_source in ('link', 'clipboard', 'manual') then in_source else 'link' end,
          next_status, score, reasons, in_device, client_ip);

  perform add_notification(inviter, me, 'referral_joined', 'points', me, null);
  perform referral_log(me, 'referral_registered',
    jsonb_build_object('inviter', inviter, 'source', in_source, 'status', next_status, 'score', score));
  if next_status = 'suspicious' then
    perform referral_log(me, 'referral_fraud_detected', jsonb_build_object('reasons', reasons, 'score', score));
  end if;

  return jsonb_build_object(
    'status', next_status,
    'inviter_name', (select display_name from profiles where id = inviter)
  );
end $$;

-- Всё для экрана «Пригласить в ChaWo». Люди 2–5 уровней не раскрываются:
-- сеть нужна для расчёта, а не как список контактов.
create function my_referral() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  s referral_settings;
  my_code text;
  levels jsonb;
begin
  if me is null then raise exception 'нужен вход'; end if;
  select * into s from referral_settings;
  my_code := referral_ensure_code(me);

  with recursive down(level, profile_id) as (
    select 1, r.invitee_id from referrals r
    where r.inviter_id = me and r.status <> 'rejected'
    union all
    select d.level + 1, r.invitee_id from down d join referrals r on r.inviter_id = d.profile_id
    where d.level < 5 and r.status <> 'rejected'
  )
  select coalesce(jsonb_agg(jsonb_build_object('level', l, 'count', c) order by l), '[]')
  into levels
  from (select level l, count(*) c from down group by level) x;

  return jsonb_build_object(
    'enabled', s.enabled,
    'code', my_code,
    'level_points', to_jsonb(s.level_points),
    'levels', levels,
    'direct', (select count(*) from referrals where inviter_id = me and status <> 'rejected'),
    'network', (select coalesce(sum((x ->> 'count')::int), 0) from jsonb_array_elements(levels) x),
    'earned', (select coalesce(sum(amount), 0) from point_transactions
               where profile_id = me and code like 'referral_level_%' and status = 'confirmed')
             - (select coalesce(sum(-amount), 0) from point_transactions
               where profile_id = me and status = 'reversed'),
    'pending', (select coalesce(sum(amount), 0) from point_transactions where profile_id = me and status = 'pending'),
    'karma', (select social_score from profiles where id = me),
    'invited_by', (select jsonb_build_object('id', p.id, 'name', p.display_name, 'avatar', p.avatar_url)
                   from referrals r join profiles p on p.id = r.inviter_id where r.invitee_id = me),
    'can_claim', not exists (select 1 from referrals where invitee_id = me)
                 and (select created_at from profiles where id = me) > now() - make_interval(days => s.claim_days),
    'invites', (
      select coalesce(jsonb_agg(row order by (row ->> 'at') desc), '[]') from (
        select jsonb_build_object(
          'id', r.invitee_id,
          'name', p.display_name,
          'avatar', p.avatar_url,
          'at', r.created_at,
          'status', r.status,
          'points', (select coalesce(sum(t.amount), 0) from point_transactions t
                     where t.profile_id = me and t.invitee_id = r.invitee_id and t.status in ('pending', 'confirmed'))
        ) row
        from referrals r join profiles p on p.id = r.invitee_id
        where r.inviter_id = me
        order by r.created_at desc
        limit 100
      ) x
    ),
    'history', (
      select coalesce(jsonb_agg(row order by (row ->> 'at') desc), '[]') from (
        select jsonb_build_object(
          'id', t.id,
          'amount', t.amount,
          'code', t.code,
          'status', t.status,
          'level', t.level,
          'reason', t.reason,
          'at', t.created_at,
          'settled_at', t.settled_at,
          'source_id', t.source_id,
          -- Имя — только у своих прямых приглашённых.
          'who', case when t.level = 1 then (select display_name from profiles where id = t.invitee_id) end
        ) row
        from point_transactions t
        where t.profile_id = me
        order by t.created_at desc
        limit 200
      ) x
    )
  );
end $$;

-- ── обработка раз в минуту ──────────────────────────────────────────────────

create function referrals_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  s referral_settings;
  r referrals;
  a record;
  t point_transactions;
  pts integer;
  given integer;
  tx uuid;
begin
  select * into s from referral_settings;
  if not s.enabled then return; end if;

  -- Не активировался вовремя.
  update referrals set status = 'expired'
  where status = 'waiting' and created_at < now() - make_interval(days => s.activation_days);

  -- Выполнил условия — начисления вверх по цепочке, пока «ожидают».
  for r in
    select * from referrals where status = 'waiting' for update skip locked
  loop
    continue when not referral_activation_ok(r.invitee_id);
    update referrals set status = 'activated', activated_at = now() where invitee_id = r.invitee_id;
    perform referral_log(r.invitee_id, 'referral_activated', jsonb_build_object('inviter', r.inviter_id));
    given := 0;
    for a in select * from referral_ancestors(r.invitee_id, coalesce(array_length(s.level_points, 1), 0)) loop
      pts := s.level_points[a.level];
      continue when pts is null or pts <= 0;
      pts := least(pts, s.max_points_per_invitee - given);
      exit when pts <= 0;
      continue when exists (select 1 from profiles where id = a.profile_id and status = 'blocked');
      insert into point_transactions (profile_id, amount, code, status, level, invitee_id, confirm_after)
      values (a.profile_id, pts, 'referral_level_' || a.level, 'pending', a.level, r.invitee_id,
              now() + make_interval(mins => s.hold_minutes))
      returning id into tx;
      given := given + pts;
      perform add_notification(a.profile_id, case when a.level = 1 then r.invitee_id end,
        'referral_reward', 'points', tx, pts::text || ':' || a.level);
      perform referral_log(a.profile_id, 'referral_reward_pending', jsonb_build_object('amount', pts, 'level', a.level));
    end loop;
  end loop;

  -- Срок проверки вышел — подтверждаем или отменяем.
  for t in
    select * from point_transactions
    where status = 'pending' and confirm_after <= now()
    for update skip locked
  loop
    if exists (select 1 from referrals where invitee_id = t.invitee_id and status = 'activated')
       and referral_activation_ok(t.invitee_id) then
      update point_transactions set status = 'confirmed', settled_at = now() where id = t.id;
      insert into score_events (profile_id, reason, delta) values (t.profile_id, t.code, t.amount);
      perform add_notification(t.profile_id, null, 'referral_confirmed', 'points', t.id, t.amount::text);
      perform referral_log(t.profile_id, 'referral_reward_confirmed', jsonb_build_object('amount', t.amount, 'level', t.level));
    else
      update point_transactions set status = 'cancelled', settled_at = now() where id = t.id;
      insert into point_transactions (profile_id, amount, code, status, level, invitee_id, source_id, reason, settled_at)
      values (t.profile_id, -t.amount, 'referral_activation_expired', 'cancelled', t.level, t.invitee_id, t.id,
              'Реферал не выполнил условия активации. Начисление отменено', now())
      returning id into tx;
      perform add_notification(t.profile_id, null, 'referral_cancelled', 'points', tx, t.amount::text);
      perform referral_log(t.profile_id, 'referral_reward_cancelled', jsonb_build_object('amount', t.amount, 'level', t.level));
    end if;
  end loop;
end $$;

-- ── ручные решения (дашборд/админ) ─────────────────────────────────────────

-- Подозрительный реферал после проверки: одобрить (вернуть в ожидание
-- активации) или отклонить.
create function referral_review(in_invitee uuid, in_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update referrals
  set status = case when in_approve then 'waiting' else 'rejected' end, reviewed_at = now()
  where invitee_id = in_invitee and status = 'suspicious';
end $$;

-- Накрутка выяснилась после подтверждения: снимаем отдельной операцией по
-- всей цепочке, исходные начисления остаются в истории.
create function referral_reverse(in_invitee uuid, in_reason text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  t point_transactions;
  tx uuid;
  n integer := 0;
begin
  for t in
    select * from point_transactions
    where invitee_id = in_invitee and code like 'referral_level_%' and status in ('confirmed', 'pending')
    for update
  loop
    if t.status = 'pending' then
      update point_transactions set status = 'cancelled', settled_at = now() where id = t.id;
    else
      insert into score_events (profile_id, reason, delta) values (t.profile_id, 'referral_fraud_reversal', -t.amount);
    end if;
    insert into point_transactions (profile_id, amount, code, status, level, invitee_id, source_id, reason, settled_at)
    values (t.profile_id, -t.amount, 'referral_fraud_reversal', 'reversed', t.level, t.invitee_id, t.id,
            coalesce(in_reason, 'Начисление снято: приглашение признано недействительным'), now())
    returning id into tx;
    perform add_notification(t.profile_id, null, 'referral_cancelled', 'points', tx, t.amount::text);
    perform referral_log(t.profile_id, 'referral_reward_reversed', jsonb_build_object('amount', t.amount, 'level', t.level));
    n := n + 1;
  end loop;
  update referrals set status = 'rejected', reviewed_at = now() where invitee_id = in_invitee;
  return n;
end $$;

-- ── уведомления ─────────────────────────────────────────────────────────────

alter table notifications drop constraint notifications_kind_check;
alter table notifications add constraint notifications_kind_check check (kind in (
  'follow', 'comment', 'reply', 'reaction', 'event_join', 'event_changed', 'event_cancelled',
  'message', 'quest_request', 'quest_join', 'quest_approved', 'quest_rejected', 'quest_removed',
  'quest_cancelled', 'need_response',
  'referral_joined', 'referral_reward', 'referral_confirmed', 'referral_cancelled'
));
-- 'points' — операция в истории баллов (тап по уведомлению открывает её).
alter table notifications drop constraint notifications_target_type_check;
alter table notifications add constraint notifications_target_type_check check (target_type in (
  'profile', 'post', 'event', 'place', 'route', 'quest', 'need', 'points'
));

-- ── права ───────────────────────────────────────────────────────────────────

revoke all on function
  track_event(text, jsonb), referral_log(uuid, text, jsonb), referral_new_code(), referral_ensure_code(uuid),
  request_ip(), referral_ancestors(uuid, integer), referral_activation_ok(uuid), report_device(text),
  claim_referral(text, text, text), my_referral(), referrals_tick(), referral_review(uuid, boolean),
  referral_reverse(uuid, text)
  from public, anon, authenticated;

grant execute on function track_event(text, jsonb), report_device(text), claim_referral(text, text, text), my_referral()
  to authenticated;

select cron.schedule('referrals-tick', '* * * * *', 'select public.referrals_tick()');
