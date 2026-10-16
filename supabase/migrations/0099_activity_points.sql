-- AP за активность в городе (шаг 1 программы амбассадоров, docs/ambassadors-program.md).
--
-- AP — это profiles.social_score, журнал баланса — score_events. Правила
-- согласованы с Алексеем 16.10.2026: платим за реакцию других людей, а не за
-- собственные клики, иначе накрутят постами.
--
--   post_like     лайк на твой пост от другого человека        1   50 в день
--   post_comment  комментарий под твоим постом (раз с человека) 2   30 в день
--   event_visit   записался до начала, ивент прошёл             10    3 в день
--   event_host    твой ивент прошёл, ≥3 записались до начала  30 + 5 за участника (до 20), 1 в день
--   quest_done    прошёл квест с отметкой прихода по коду      20    3 в день
--   quest_host    кто-то прошёл твой квест с отметкой прихода   5   20 в день
--   рефералы — как в 0059, без изменений.
--
-- Не начисляется: себе от себя, от виртуальных авторов и заблокированных,
-- от людей без подтверждённого телефона (лайк, комментарий, чужой квест,
-- гость на чужом ивенте), за то, что удалили до подтверждения. Начисление сначала pending и через
-- hold_hours проверяется заново. Потолок за активность — 300 AP в сутки по
-- Москве, рефералы сверху. Счёт с момента миграции: старое не оплачивается.
--
-- Старые правила (лайк поста ±1, лайк комментария ±1, запись на ивент ±1
-- автору, ночной бонус за пятёрку лайков) снимаются: иначе тот же лайк
-- засчитывался бы дважды. Набранный ими баланс остаётся.
--
-- В каждую запись score_events пишется город получателя на момент
-- начисления: сезонный рейтинг города считается по ним, переезд посреди
-- сезона очки с собой не переносит.

-- ── старые правила ──────────────────────────────────────────────────────────

drop trigger if exists on_post_like on post_likes;
drop trigger if exists on_comment_like on comment_likes;
drop trigger if exists on_event_join on event_participants;
drop function if exists apply_like_score();
drop function if exists apply_comment_like_score();
drop function if exists apply_event_join_score();
select cron.unschedule('like-bonus-tick') where exists (select 1 from cron.job where jobname = 'like-bonus-tick');
drop function if exists like_bonus_tick();

-- ── город в журнале AP ──────────────────────────────────────────────────────

alter table score_events add column city text;
create index score_events_city_idx on score_events (city, created_at);

-- Рефералы и всё прочее пишут без города — подставляем текущий город получателя.
create function score_event_city() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.city is null then
    select city into new.city from profiles where id = new.profile_id;
  end if;
  return new;
end $$;

create trigger score_event_city before insert on score_events
  for each row execute function score_event_city();

-- ── правила и настройки ─────────────────────────────────────────────────────

create table activity_rules (
  code        text primary key,
  amount      integer not null check (amount > 0),
  daily_limit integer check (daily_limit is null or daily_limit > 0),
  hold_hours  integer not null default 24 check (hold_hours >= 0),
  note        text
);

insert into activity_rules (code, amount, daily_limit, hold_hours, note) values
  ('post_like',    1, 50, 24, 'лайк на твой пост от другого человека'),
  ('post_comment', 2, 30, 24, 'комментарий под твоим постом, один раз с человека на пост'),
  ('event_visit', 10,  3, 24, 'записался до начала ивента, ивент прошёл'),
  ('event_host',  30,  1, 24, 'твой ивент прошёл с участниками; надбавка за участника — в activity_settings'),
  ('quest_done',  20,  3, 24, 'прошёл квест с отметкой прихода'),
  ('quest_host',   5, 20, 24, 'кто-то прошёл твой квест с отметкой прихода');

create table activity_settings (
  id                    boolean primary key default true check (id),
  started_at            timestamptz not null default now(),
  daily_cap             integer not null default 300,
  event_host_min_guests integer not null default 3,
  event_host_per_guest  integer not null default 5,
  event_host_max_guests integer not null default 20
);

insert into activity_settings default values;

-- ── начисления до подтверждения ─────────────────────────────────────────────

create table activity_awards (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references profiles on delete cascade,
  code          text not null references activity_rules,
  amount        integer not null check (amount > 0),
  city          text,
  -- Без внешнего ключа: set null при удалении аккаунта столкнул бы строки в activity_awards_once.
  actor_id      uuid,
  source_id     uuid not null,
  status        text not null default 'pending' check (status in ('pending', 'confirmed', 'cancelled')),
  confirm_after timestamptz not null,
  settled_at    timestamptz,
  created_at    timestamptz not null default now()
);

-- Одно начисление на пару «за что — от кого»: снять и снова поставить лайк не выйдет.
create unique index activity_awards_once on activity_awards
  (code, source_id, profile_id, coalesce(actor_id, '00000000-0000-0000-0000-000000000000'));
create index activity_awards_day_idx on activity_awards (profile_id, created_at);
create index activity_awards_pending_idx on activity_awards (confirm_after) where status = 'pending';

-- Ивенты, по которым итоги уже подведены (в том числе те, где начислять было нечего).
create table activity_events_settled (
  event_id   uuid primary key references events on delete cascade,
  settled_at timestamptz not null default now()
);

alter table activity_rules enable row level security;
alter table activity_settings enable row level security;
alter table activity_awards enable row level security;
alter table activity_events_settled enable row level security;
revoke all on activity_rules, activity_settings, activity_awards, activity_events_settled
  from public, anon, authenticated;

-- Правила и лимиты читает экран «Activity Points» для справки.
create policy activity_rules_read on activity_rules for select to authenticated using (true);
grant select on activity_rules to authenticated;
create policy activity_settings_read on activity_settings for select to authenticated using (true);
grant select on activity_settings to authenticated;

create policy activity_awards_own on activity_awards for select to authenticated
  using (profile_id = auth.uid());
grant select on activity_awards to authenticated;

-- ── начисление ──────────────────────────────────────────────────────────────

create function activity_award(
  in_profile uuid, in_code text, in_source uuid,
  in_actor uuid default null, in_amount integer default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  r activity_rules;
  s activity_settings;
  day_start timestamptz := date_trunc('day', now() at time zone 'Europe/Moscow') at time zone 'Europe/Moscow';
  recipient_city text;
  used integer;
  pts integer;
begin
  if in_profile is null or in_profile = in_actor then
    return;
  end if;
  select * into r from activity_rules where code = in_code;
  if not found then
    return;
  end if;
  select * into s from activity_settings;
  if exists (select 1 from bot_authors where profile_id = in_profile or profile_id = in_actor)
     or exists (select 1 from profiles where id = in_actor and status = 'blocked') then
    return;
  end if;
  -- Лайки и комментарии с фейков не в счёт: от кого начисление — у того подтверждён телефон.
  if in_actor is not null
     and not exists (select 1 from profile_phones where profile_id = in_actor and verified) then
    return;
  end if;
  select city into recipient_city from profiles where id = in_profile and status <> 'blocked';
  if not found then
    return;
  end if;

  -- Лимиты считаются по уже записанному: параллельные начисления одному человеку по очереди.
  perform pg_advisory_xact_lock(hashtext('activity_award'), hashtext(in_profile::text));
  if r.daily_limit is not null and r.daily_limit <= (
       select count(*) from activity_awards
       where profile_id = in_profile and code = in_code and status <> 'cancelled' and created_at >= day_start) then
    return;
  end if;
  select coalesce(sum(amount), 0) into used from activity_awards
  where profile_id = in_profile and status <> 'cancelled' and created_at >= day_start;
  pts := least(coalesce(in_amount, r.amount), s.daily_cap - used);
  if pts <= 0 then
    return;
  end if;

  insert into activity_awards (profile_id, code, amount, city, actor_id, source_id, confirm_after)
  values (in_profile, in_code, pts, recipient_city, in_actor, in_source, now() + make_interval(hours => r.hold_hours))
  on conflict do nothing;
end $$;

create function activity_on_post_like() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform activity_award((select author_id from posts where id = new.post_id), 'post_like', new.post_id, new.profile_id);
  return new;
end $$;

create trigger activity_post_like after insert on post_likes
  for each row execute function activity_on_post_like();

create function activity_on_post_comment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform activity_award((select author_id from posts where id = new.post_id), 'post_comment', new.post_id, new.author_id);
  return new;
end $$;

create trigger activity_post_comment after insert on post_comments
  for each row execute function activity_on_post_comment();

create function activity_on_quest_completed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  host uuid;
begin
  -- Завершить квест можно и не приходя; платим только с отметкой прихода по коду.
  if new.status <> 'completed' or new.arrived_at is null
     or (tg_op = 'UPDATE' and old.status = 'completed') then
    return new;
  end if;
  select author_id into host from quests where id = new.quest_id;
  if host is null or host = new.profile_id then
    return new;
  end if;
  -- Оба замка в одном порядке: встречные завершения квестов друг друга не зациклятся.
  perform pg_advisory_xact_lock(hashtext('activity_award'), hashtext(least(host, new.profile_id)::text));
  perform pg_advisory_xact_lock(hashtext('activity_award'), hashtext(greatest(host, new.profile_id)::text));
  perform activity_award(new.profile_id, 'quest_done', new.quest_id);
  perform activity_award(host, 'quest_host', new.quest_id, new.profile_id);
  return new;
end $$;

create trigger activity_quest_completed after insert or update of status on quest_participations
  for each row execute function activity_on_quest_completed();

-- ── итоги ивентов и подтверждение (раз в 5 минут) ───────────────────────────

create function activity_points_tick() returns integer
language plpgsql security definer set search_path = public as $$
declare
  s activity_settings;
  e record;
  guests integer;
  a activity_awards;
  ok boolean;
  done integer := 0;
begin
  select * into s from activity_settings;

  -- Ивент считается прошедшим по ends_at, без него — через 3 часа после начала.
  for e in
    select ev.id, ev.author_id, ev.starts_at from events ev
    where ev.status <> 'blocked'
      and coalesce(ev.ends_at, ev.starts_at + interval '3 hours') between s.started_at and now()
      and not exists (select 1 from activity_events_settled d where d.event_id = ev.id)
    for no key update skip locked
  loop
    -- Записаться можно и после конца ивента — такие записи не в счёт.
    perform activity_award(p.profile_id, 'event_visit', e.id)
    from event_participants p
    where p.event_id = e.id and p.profile_id <> e.author_id and p.joined_at < e.starts_at;

    select count(*) into guests
    from event_participants p join profiles pr on pr.id = p.profile_id
    where p.event_id = e.id and p.profile_id <> e.author_id and p.joined_at < e.starts_at
      and pr.status <> 'blocked'
      and exists (select 1 from profile_phones ph where ph.profile_id = p.profile_id and ph.verified)
      and not exists (select 1 from bot_authors b where b.profile_id = p.profile_id);
    if guests >= s.event_host_min_guests then
      perform activity_award(e.author_id, 'event_host', e.id, null,
        (select amount from activity_rules where code = 'event_host')
          + s.event_host_per_guest * least(guests, s.event_host_max_guests));
    end if;

    insert into activity_events_settled (event_id) values (e.id);
  end loop;

  for a in
    select * from activity_awards
    where status = 'pending' and confirm_after <= now()
    for update skip locked
  loop
    -- За сутки ожидания могли заблокировать и получателя, и того, от кого начисление.
    ok := exists (select 1 from profiles where id = a.profile_id and status <> 'blocked')
      and (a.actor_id is null or (
        exists (select 1 from profiles where id = a.actor_id and status <> 'blocked')
        and not exists (select 1 from bot_authors where profile_id = a.actor_id)))
      and case a.code
        when 'post_like' then exists (
          select 1 from post_likes l join posts p on p.id = l.post_id
          where l.post_id = a.source_id and l.profile_id = a.actor_id and p.status <> 'blocked')
        when 'post_comment' then exists (
          select 1 from post_comments c join posts p on p.id = c.post_id
          where c.post_id = a.source_id and c.author_id = a.actor_id
            and c.deleted_at is null and c.status <> 'blocked' and p.status <> 'blocked')
        when 'quest_done' then exists (
          select 1 from quest_participations q join quests qs on qs.id = q.quest_id
          where q.quest_id = a.source_id and q.profile_id = a.profile_id and q.arrived_at is not null
            and q.status = 'completed' and qs.moderation <> 'blocked' and qs.status <> 'cancelled')
        when 'quest_host' then exists (
          select 1 from quest_participations q join quests qs on qs.id = q.quest_id
          where q.quest_id = a.source_id and q.profile_id = a.actor_id and q.arrived_at is not null
            and q.status = 'completed' and qs.moderation <> 'blocked' and qs.status <> 'cancelled')
        when 'event_visit' then exists (
          select 1 from event_participants p join events ev on ev.id = p.event_id
          where p.event_id = a.source_id and p.profile_id = a.profile_id
            and p.joined_at < ev.starts_at and ev.status <> 'blocked')
        when 'event_host' then exists (
          select 1 from events ev where ev.id = a.source_id and ev.status <> 'blocked')
        else true
      end;

    if ok then
      update activity_awards set status = 'confirmed', settled_at = now() where id = a.id;
      insert into score_events (profile_id, reason, delta, city) values (a.profile_id, a.code, a.amount, a.city);
      done := done + 1;
    else
      update activity_awards set status = 'cancelled', settled_at = now() where id = a.id;
    end if;
  end loop;

  return done;
end $$;

revoke all on function score_event_city() from public, anon, authenticated;
revoke all on function activity_award(uuid, text, uuid, uuid, integer) from public, anon, authenticated;
revoke all on function activity_on_post_like() from public, anon, authenticated;
revoke all on function activity_on_post_comment() from public, anon, authenticated;
revoke all on function activity_on_quest_completed() from public, anon, authenticated;
revoke all on function activity_points_tick() from public, anon, authenticated;

select cron.schedule('activity-points-tick', '*/5 * * * *', 'select public.activity_points_tick()')
where not exists (select 1 from cron.job where jobname = 'activity-points-tick');
