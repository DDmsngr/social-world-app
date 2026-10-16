-- Режимы входа на событие (просьба тестировщика Артура 16.10.2026, решения Алексея):
--   free    — записаться сразу (как было);
--   request — запрос организатору: человек сам рассказывает о себе, организатор
--             принимает или отклоняет;
--   invite  — встреча видна только тем, кого организатор позвал: приглашённые
--             попадают в участники сразу.
-- Лимит участников: число или null — без лимита. Приглашение работает в любом
-- режиме. Всё, что меняет состав участников, идёт через функции ниже: прямая
-- запись себя в event_participants разрешена только в режиме free.

alter table events
  add column join_mode text not null default 'free' check (join_mode in ('free', 'request', 'invite')),
  add column max_participants integer check (max_participants is null or max_participants between 1 and 10000);

-- ── видимость ───────────────────────────────────────────────────────────────

-- Событие видно всем, кроме встреч «по приглашению»: их видят организатор и участники.
create function event_visible(in_event uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from events e
    where e.id = in_event and e.status = 'active'
      and (e.join_mode <> 'invite'
           or e.author_id = auth.uid()
           or exists (select 1 from event_participants p
                      where p.event_id = e.id and p.profile_id = auth.uid()))
  )
$$;

-- Можно ли записаться самому: только свободный вход и только если есть места.
create function event_free_join_ok(in_event uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from events e
    where e.id = in_event and e.status = 'active' and e.join_mode = 'free'
      and (e.max_participants is null
           or (select count(*) from event_participants p where p.event_id = e.id) < e.max_participants)
  )
$$;

revoke all on function event_visible(uuid), event_free_join_ok(uuid) from public, anon;
grant execute on function event_visible(uuid), event_free_join_ok(uuid) to authenticated;

drop policy "события видны всем авторизованным" on events;
create policy events_visible on events for select to authenticated
  using (status = 'active' and (join_mode <> 'invite' or author_id = auth.uid() or event_visible(id)));

drop policy "участники видны всем авторизованным" on event_participants;
create policy event_participants_visible on event_participants for select to authenticated
  using (profile_id = auth.uid() or event_visible(event_id));

drop policy "записываю на событие только себя" on event_participants;
create policy event_participants_join_free on event_participants for insert to authenticated
  with check (auth.uid() = profile_id and event_free_join_ok(event_id));

-- Лимит держится и для записи через функции (принятый запрос, приглашение).
create function event_capacity_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cap integer;
begin
  select max_participants into cap from events where id = new.event_id for share;
  if cap is not null
     and (select count(*) from event_participants where event_id = new.event_id) >= cap then
    raise exception 'event_full' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger event_capacity_check before insert on event_participants
  for each row execute function event_capacity_check();

-- Организатор не получает «X записался» про тех, кого сам позвал или принял:
-- функции приглашения и решения по запросу ставят этот флаг на свою транзакцию.
create or replace function trg_notify_event_join() returns trigger
language plpgsql security definer set search_path = public as $$
declare ev_author uuid; ev_title text;
begin
  if current_setting('app.skip_join_notify', true) = '1' then
    return new;
  end if;
  select author_id, title into ev_author, ev_title from events where id = new.event_id;
  perform add_notification(ev_author, new.profile_id, 'event_join', 'event', new.event_id, ev_title, null);
  return new;
end;
$$;

-- ── запросы на участие ──────────────────────────────────────────────────────

create table event_join_requests (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references events on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  about      text not null check (char_length(about) between 5 and 400),
  message    text check (message is null or char_length(message) <= 300),
  status     text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique (event_id, profile_id)
);

create index event_join_requests_event_idx on event_join_requests (event_id, status, created_at);

alter table event_join_requests enable row level security;
revoke all on event_join_requests from public, anon, authenticated;

-- Свои запросы человек видит напрямую; организатор — через функцию списка.
create policy event_join_requests_own on event_join_requests for select to authenticated
  using (profile_id = auth.uid());
grant select on event_join_requests to authenticated;

-- Просьба, ответ на неё и приглашение — не «события вокруг», а личное: они
-- приходят всем, даже если общая категория «События» выключена (по умолчанию так).
create or replace function notification_category(in_kind text) returns text
language sql immutable set search_path = public as $$
  select case
    when in_kind in ('event_request', 'event_request_approved', 'event_request_rejected', 'event_invited') then 'other'
    when in_kind = 'message' then 'messages'
    when in_kind in ('comment', 'reply') then 'comments'
    when in_kind = 'reaction' then 'likes'
    when in_kind = 'mention' then 'mentions'
    when in_kind = 'follow' then 'follows'
    when in_kind like 'event\_%' then 'events'
    when in_kind like 'quest\_%' then 'quests'
    when in_kind = 'need_response' then 'needs'
    when in_kind like 'referral\_%' then 'points'
    else 'other'
  end;
$$;

alter table notifications drop constraint notifications_kind_check;
alter table notifications add constraint notifications_kind_check check (kind in (
  'follow', 'comment', 'reply', 'reaction',
  'event_join', 'event_changed', 'event_cancelled', 'message',
  'quest_request', 'quest_join', 'quest_approved', 'quest_rejected',
  'quest_removed', 'quest_cancelled', 'need_response',
  'referral_joined', 'referral_reward', 'referral_confirmed', 'referral_cancelled',
  'mention',
  'event_request', 'event_request_approved', 'event_request_rejected', 'event_invited'
));

-- Человек просит войти. Возвращает 'requested'.
create function event_request_join(in_event uuid, in_about text, in_message text default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  e events;
  me uuid := auth.uid();
  req event_join_requests;
begin
  if me is null then raise exception 'authentication required'; end if;
  select * into e from events where id = in_event and status = 'active';
  if not found or e.join_mode <> 'request' then
    raise exception 'event_not_accepting_requests' using errcode = 'P0001';
  end if;
  if e.author_id = me or is_hidden_between(me, e.author_id) then
    raise exception 'event_not_accepting_requests' using errcode = 'P0001';
  end if;
  if coalesce(e.ends_at, e.starts_at + interval '3 hours') <= now() then
    raise exception 'event_over' using errcode = 'P0001';
  end if;
  if exists (select 1 from event_participants where event_id = in_event and profile_id = me) then
    raise exception 'already_participant' using errcode = 'P0001';
  end if;
  -- Не больше 20 ожидающих запросов на человека: от рассылки по всем встречам.
  if (select count(*) from event_join_requests where profile_id = me and status = 'pending') >= 20 then
    raise exception 'too_many_requests' using errcode = 'P0001';
  end if;

  select * into req from event_join_requests where event_id = in_event and profile_id = me for update;
  if found then
    -- Отказ окончательный: повторные просьбы после отказа — это давление.
    if req.status in ('rejected', 'approved', 'pending') then
      raise exception 'request_already_decided' using errcode = 'P0001';
    end if;
    update event_join_requests
       set status = 'pending', about = btrim(in_about), message = nullif(btrim(coalesce(in_message, '')), ''),
           created_at = now(), decided_at = null
     where id = req.id;
  else
    insert into event_join_requests (event_id, profile_id, about, message)
    values (in_event, me, btrim(in_about), nullif(btrim(coalesce(in_message, '')), ''));
  end if;

  perform add_notification(e.author_id, me, 'event_request', 'event', in_event, left(btrim(in_about), 80), null);
  return 'requested';
end $$;

create function event_withdraw_request(in_event uuid) returns void
language sql security definer set search_path = public as $$
  update event_join_requests set status = 'withdrawn', decided_at = now()
  where event_id = in_event and profile_id = auth.uid() and status = 'pending'
$$;

-- Запросы к моей встрече: сначала ожидающие.
create function event_requests_list(in_event uuid)
returns table (request_id uuid, profile_id uuid, display_name text, avatar_url text,
               about text, message text, status text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.profile_id, p.display_name, p.avatar_url, r.about, r.message, r.status, r.created_at
  from event_join_requests r
  join profiles p on p.id = r.profile_id and p.status <> 'blocked'
  where r.event_id = in_event
    and exists (select 1 from events e where e.id = in_event and e.author_id = auth.uid())
    and r.status <> 'withdrawn'
  order by (r.status = 'pending') desc, r.created_at desc
  limit 200
$$;

-- Организатор решает по запросу. Принятый сразу становится участником.
create function event_decide_request(in_request uuid, in_approve boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  r event_join_requests;
  e events;
begin
  select * into r from event_join_requests where id = in_request for update;
  if not found then raise exception 'request_not_found' using errcode = 'P0001'; end if;
  select * into e from events where id = r.event_id and status = 'active';
  if not found or e.author_id is distinct from auth.uid() then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if r.status <> 'pending' then
    raise exception 'request_already_decided' using errcode = 'P0001';
  end if;

  if in_approve then
    perform set_config('app.skip_join_notify', '1', true);
    insert into event_participants (event_id, profile_id) values (r.event_id, r.profile_id)
    on conflict do nothing;
    update event_join_requests set status = 'approved', decided_at = now() where id = r.id;
    perform add_notification(r.profile_id, e.author_id, 'event_request_approved', 'event', e.id, e.title, null);
    return 'approved';
  end if;
  update event_join_requests set status = 'rejected', decided_at = now() where id = r.id;
  perform add_notification(r.profile_id, e.author_id, 'event_request_rejected', 'event', e.id, e.title, null);
  return 'rejected';
end $$;

-- ── приглашения ─────────────────────────────────────────────────────────────

-- Организатор зовёт людей: они сразу становятся участниками. Кого не удалось
-- добавить из-за лимита — считаем отдельно. Не больше 50 за вызов.
create function event_invite(in_event uuid, in_profiles uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e events;
  me uuid := auth.uid();
  pid uuid;
  added integer := 0;
  full_count integer := 0;
  skipped integer := 0;
begin
  select * into e from events where id = in_event and status = 'active';
  if not found or e.author_id is distinct from me then
    raise exception 'event_not_found' using errcode = 'P0001';
  end if;
  if coalesce(array_length(in_profiles, 1), 0) > 50 then
    raise exception 'too_many_invites' using errcode = 'P0001';
  end if;
  if coalesce(e.ends_at, e.starts_at + interval '3 hours') <= now() then
    raise exception 'event_over' using errcode = 'P0001';
  end if;

  perform set_config('app.skip_join_notify', '1', true);
  foreach pid in array coalesce(in_profiles, '{}') loop
    if pid = me
       or not exists (select 1 from profiles where id = pid and status <> 'blocked')
       or is_hidden_between(me, pid)
       or exists (select 1 from event_participants where event_id = in_event and profile_id = pid) then
      skipped := skipped + 1;
      continue;
    end if;
    begin
      insert into event_participants (event_id, profile_id) values (in_event, pid);
      update event_join_requests set status = 'approved', decided_at = now()
       where event_id = in_event and profile_id = pid and status = 'pending';
      perform add_notification(pid, me, 'event_invited', 'event', in_event, e.title, null);
      added := added + 1;
    exception when sqlstate 'P0001' then
      full_count := full_count + 1;
    end;
  end loop;
  return jsonb_build_object('added', added, 'full', full_count, 'skipped', skipped);
end $$;

-- Кого можно позвать: друзья (я подписан или подписан на меня), ещё не участники.
create function event_invite_candidates(in_event uuid, in_query text default null)
returns table (profile_id uuid, display_name text, username text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.avatar_url
  from profiles p
  where exists (select 1 from events e where e.id = in_event and e.author_id = auth.uid())
    and p.status <> 'blocked' and p.id <> auth.uid()
    and friend_rank(auth.uid(), p.id) > 0
    and not is_hidden_between(auth.uid(), p.id)
    and not exists (select 1 from event_participants ep where ep.event_id = in_event and ep.profile_id = p.id)
    and (nullif(btrim(coalesce(in_query, '')), '') is null
         or p.display_name ilike '%' || btrim(in_query) || '%'
         or p.username ilike '%' || btrim(in_query) || '%')
  order by friend_rank(auth.uid(), p.id) desc, p.display_name
  limit 60
$$;

revoke all on function event_request_join(uuid, text, text), event_withdraw_request(uuid),
  event_requests_list(uuid), event_decide_request(uuid, boolean), event_invite(uuid, uuid[]),
  event_invite_candidates(uuid, text), event_capacity_check() from public, anon, authenticated;
grant execute on function event_request_join(uuid, text, text), event_withdraw_request(uuid),
  event_requests_list(uuid), event_decide_request(uuid, boolean), event_invite(uuid, uuid[]),
  event_invite_candidates(uuid, text) to authenticated;

-- ── лента событий: режим, лимит, мой запрос, число ожидающих (организатору) ──

drop function city_events(integer, uuid);

create function city_events(
  in_limit integer default 50,
  in_event uuid default null
)
returns table (
  id                   uuid,
  author_id            uuid,
  author_name          text,
  avatar_url           text,
  title                text,
  description          text,
  starts_at            timestamptz,
  ends_at              timestamptz,
  place_title          text,
  cover_url            text,
  created_at           timestamptz,
  participant_count    bigint,
  joined_by_me         boolean,
  place_id             uuid,
  place_latitude       double precision,
  place_longitude      double precision,
  route_points         jsonb,
  participants_preview jsonb,
  join_mode            text,
  max_participants     integer,
  my_request_status    text,
  pending_requests     bigint
)
language sql stable security definer set search_path = public as $$
  select e.id,
         e.author_id,
         pr.display_name,
         pr.avatar_url,
         e.title,
         e.description,
         e.starts_at,
         e.ends_at,
         pl.title,
         e.cover_url,
         e.created_at,
         count(ep.profile_id),
         coalesce(bool_or(ep.profile_id = auth.uid()), false),
         pl.id,
         st_y(pl.geo::geometry),
         st_x(pl.geo::geometry),
         e.route_points,
         (
           select coalesce(jsonb_agg(jsonb_build_object(
                    'id', x.profile_id, 'name', x.display_name,
                    'avatar_url', x.avatar_url, 'friend', x.fr > 0
                  ) order by x.fr desc, x.joined_at), '[]'::jsonb)
           from (
             select ep2.profile_id, p2.display_name, p2.avatar_url, ep2.joined_at,
                    friend_rank(auth.uid(), ep2.profile_id) as fr
             from event_participants ep2
             join profiles p2 on p2.id = ep2.profile_id
             where ep2.event_id = e.id
               and p2.status <> 'blocked'
               and not is_hidden_between(auth.uid(), ep2.profile_id)
             order by friend_rank(auth.uid(), ep2.profile_id) desc, ep2.joined_at
             limit 4
           ) x
         ),
         e.join_mode,
         e.max_participants,
         (select r.status from event_join_requests r
           where r.event_id = e.id and r.profile_id = auth.uid()),
         case when e.author_id = auth.uid()
              then (select count(*) from event_join_requests r where r.event_id = e.id and r.status = 'pending')
              else 0 end
  from events e
  join profiles pr on pr.id = e.author_id
  left join places pl on pl.id = e.place_id
  left join event_participants ep on ep.event_id = e.id
  where e.status = 'active'
    and (in_event is null or e.id = in_event)
    and pr.status <> 'blocked'
    and not is_hidden_between(auth.uid(), e.author_id)
    -- Встречи «по приглашению» видят организатор и приглашённые.
    and (e.join_mode <> 'invite'
         or e.author_id = auth.uid()
         or exists (select 1 from event_participants me where me.event_id = e.id and me.profile_id = auth.uid()))
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and (
          (r.target = 'event' and r.target_id = e.id) or
          (r.target = 'profile' and r.target_id = e.author_id)
        )
    )
  group by e.id, pr.id, pl.id
  order by e.starts_at asc
  limit least(in_limit, 100);
$$;

revoke all on function city_events(integer, uuid) from public, anon;
grant execute on function city_events(integer, uuid) to authenticated;
