-- Маршруты событий, участники, центр уведомлений, слой активности карты.
--
-- Зависит от 0015 (is_hidden_between, follows, user_blocks).

-- ── маршрут события ─────────────────────────────────────────────────────────
-- Маршрут — последовательность точек [{lat, lng, title}, ...] прямо в строке
-- события. Отдельная таблица потребовала бы вставки в несколько запросов без
-- транзакции (та же проблема, что DATA-1 у маршрутов прогулок); jsonb ложится
-- одним INSERT вместе с событием, порядок задаёт порядок в массиве.
-- Прокладка по дорогам — следующий этап: это те же точки, только с геометрией.

alter table events
  add column route_points jsonb not null default '[]'::jsonb
    check (
      jsonb_typeof(route_points) = 'array'
      and jsonb_array_length(route_points) <= 25
    );

drop function if exists city_events(integer);

create function city_events(
  in_limit integer default 50,
  in_event uuid default null
)
returns table (
  id                uuid,
  author_id         uuid,
  author_name       text,
  avatar_url        text,
  title             text,
  description       text,
  starts_at         timestamptz,
  ends_at           timestamptz,
  place_title       text,
  cover_url         text,
  created_at        timestamptz,
  participant_count bigint,
  joined_by_me      boolean,
  place_id          uuid,
  place_latitude    double precision,
  place_longitude   double precision,
  route_points      jsonb
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
         e.route_points
  from events e
  join profiles pr on pr.id = e.author_id
  left join places pl on pl.id = e.place_id
  left join event_participants ep on ep.event_id = e.id
  where e.status = 'active'
    and (in_event is null or e.id = in_event)
    and pr.status <> 'blocked'
    and not is_hidden_between(auth.uid(), e.author_id)
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

revoke all on function city_events from public;
grant execute on function city_events to authenticated;

create function event_participants_list(in_event uuid, in_limit integer default 100)
returns table (profile_id uuid, display_name text, avatar_url text, joined_at timestamptz)
language sql stable security definer set search_path = public as $$
  select ep.profile_id, p.display_name, p.avatar_url, ep.joined_at
  from event_participants ep
  join profiles p on p.id = ep.profile_id
  where ep.event_id = in_event
    and p.status <> 'blocked'
    and not is_hidden_between(auth.uid(), ep.profile_id)
  order by ep.joined_at
  limit least(in_limit, 200);
$$;

revoke all on function event_participants_list from public;
grant execute on function event_participants_list to authenticated;

-- ── уведомления ─────────────────────────────────────────────────────────────
-- Таблица одновременно и центр уведомлений в приложении, и очередь для
-- будущих push: отправщик (Edge Function + FCM) читает непрочитанные строки.
-- Пишут в неё только триггеры ниже; клиент читает свои и отмечает прочитанным.

create table notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references profiles on delete cascade,
  actor_id     uuid references profiles on delete set null,
  kind         text not null check (kind in (
    'follow', 'comment', 'reply', 'reaction',
    'event_join', 'event_changed', 'event_cancelled', 'message'
  )),
  target_type  text not null check (target_type in ('profile', 'post', 'event', 'place', 'route')),
  target_id    uuid not null,
  title        text,
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);

create index notifications_recipient_idx
  on notifications (recipient_id, created_at desc);
create index notifications_unread_idx
  on notifications (recipient_id) where read_at is null;

alter table notifications enable row level security;

create policy notifications_select_own
  on notifications for select to authenticated using (recipient_id = auth.uid());

create function add_notification(
  in_recipient uuid,
  in_actor uuid,
  in_kind text,
  in_target_type text,
  in_target uuid,
  in_title text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if in_recipient is null or in_recipient = in_actor then return; end if;
  if in_actor is not null and is_hidden_between(in_recipient, in_actor) then return; end if;

  -- Повторный лайк/отписка-подписка не должны сыпать одинаковыми строками.
  if exists (
    select 1 from notifications n
    where n.recipient_id = in_recipient
      and n.actor_id is not distinct from in_actor
      and n.kind = in_kind
      and n.target_id = in_target
      and n.read_at is null
  ) then return; end if;

  insert into notifications (recipient_id, actor_id, kind, target_type, target_id, title)
  values (in_recipient, in_actor, in_kind, in_target_type, in_target, left(in_title, 120));
end;
$$;

revoke all on function add_notification from public;

create function trg_notify_follow() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.target_type = 'profile' then
    perform add_notification(new.target_id, new.follower_id, 'follow', 'profile', new.follower_id);
  end if;
  return new;
end;
$$;
create trigger notify_on_follow after insert on follows
  for each row execute function trg_notify_follow();

create function trg_notify_reaction() returns trigger
language plpgsql security definer set search_path = public as $$
declare post_author uuid; post_text text;
begin
  select author_id, coalesce(title, body) into post_author, post_text
  from posts where id = new.post_id;
  perform add_notification(post_author, new.profile_id, 'reaction', 'post', new.post_id, post_text);
  return new;
end;
$$;
create trigger notify_on_reaction after insert on post_likes
  for each row execute function trg_notify_reaction();

create function trg_notify_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare post_author uuid; parent_author uuid;
begin
  select author_id into post_author from posts where id = new.post_id;
  if new.parent_id is not null then
    select author_id into parent_author from post_comments where id = new.parent_id;
    perform add_notification(parent_author, new.author_id, 'reply', 'post', new.post_id, new.body);
  end if;
  -- Автору поста — только если это не тот же человек, что уже получил «ответ».
  if parent_author is distinct from post_author then
    perform add_notification(post_author, new.author_id, 'comment', 'post', new.post_id, new.body);
  end if;
  return new;
end;
$$;
create trigger notify_on_comment after insert on post_comments
  for each row execute function trg_notify_comment();

create function trg_notify_event_join() returns trigger
language plpgsql security definer set search_path = public as $$
declare ev_author uuid; ev_title text;
begin
  select author_id, title into ev_author, ev_title from events where id = new.event_id;
  perform add_notification(ev_author, new.profile_id, 'event_join', 'event', new.event_id, ev_title);
  return new;
end;
$$;
create trigger notify_on_event_join after insert on event_participants
  for each row execute function trg_notify_event_join();

create function trg_notify_event_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.title is distinct from old.title
     or new.starts_at is distinct from old.starts_at
     or new.ends_at is distinct from old.ends_at
     or new.place_id is distinct from old.place_id
     or new.route_points is distinct from old.route_points then
    for r in select profile_id from event_participants where event_id = new.id loop
      perform add_notification(r.profile_id, new.author_id, 'event_changed', 'event', new.id, new.title);
    end loop;
  end if;
  return new;
end;
$$;
create trigger notify_on_event_changed after update on events
  for each row execute function trg_notify_event_changed();

create function trg_notify_event_cancelled() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select profile_id from event_participants where event_id = old.id loop
    perform add_notification(r.profile_id, old.author_id, 'event_cancelled', 'event', old.id, old.title);
  end loop;
  return old;
end;
$$;
-- before delete: после удаления участников каскадом получателей уже не найти.
create trigger notify_on_event_cancelled before delete on events
  for each row execute function trg_notify_event_cancelled();

create function my_notifications(in_limit integer default 50)
returns table (
  id           uuid,
  kind         text,
  actor_id     uuid,
  actor_name   text,
  actor_avatar text,
  target_type  text,
  target_id    uuid,
  title        text,
  created_at   timestamptz,
  read_at      timestamptz
)
language sql stable security definer set search_path = public as $$
  select n.id, n.kind, n.actor_id, p.display_name, p.avatar_url,
         n.target_type, n.target_id, n.title, n.created_at, n.read_at
  from notifications n
  left join profiles p on p.id = n.actor_id
  where n.recipient_id = auth.uid()
    and (n.actor_id is null or not is_hidden_between(auth.uid(), n.actor_id))
  order by n.created_at desc
  limit least(in_limit, 100);
$$;

create function mark_notifications_read(in_ids uuid[] default null) returns void
language sql security definer set search_path = public as $$
  update notifications
     set read_at = now()
   where recipient_id = auth.uid()
     and read_at is null
     and (in_ids is null or id = any(in_ids));
$$;

revoke all on function my_notifications, mark_notifications_read from public;
grant execute on function my_notifications, mark_notifications_read to authenticated;

-- ── слой активности ─────────────────────────────────────────────────────────
-- Единая модель: фильтры пользователя → релевантные объекты → вес каждого
-- (тип, участники, свежесть) → сглаженная сумма по ячейкам сетки → клиент
-- рисует готовые зоны. Все коэффициенты лежат в activity_config: менять их
-- можно UPDATE'ом, без релиза приложения.
--
-- Время берётся из параметра in_at, а не из now(): та же функция посчитает
-- «что будет в 20:00» для временной шкалы. Инвертировать оценку («где
-- спокойнее») клиент может сам — score нормирован в 0..1.

create table activity_config (
  key   text primary key,
  value double precision not null,
  note  text
);

insert into activity_config (key, value, note) values
  ('cell_size_m',        600,  'размер ячейки сетки, м'),
  ('spread_m',           450,  'радиус сглаживания: вклад объекта затухает по гауссу'),
  ('w_event',            3.0,  'базовый вес события'),
  ('w_participant',      0.15, 'надбавка события за каждого участника (до 50)'),
  ('w_place',            0.6,  'вес места (не зависит от времени)'),
  ('w_moment',           1.5,  'вес свежего момента'),
  ('half_life_event_h',  3.0,  'период полураспада веса события по времени до/после начала, ч'),
  ('half_life_moment_h', 6.0,  'период полураспада веса момента, ч'),
  ('event_horizon_h',    12.0, 'события позже этого горизонта в слой не входят, ч'),
  ('event_past_h',       2.0,  'закончившиеся события учитываются не дольше, ч'),
  ('moment_max_age_h',   36.0, 'моменты старше этого в слой не входят, ч'),
  ('ref_score',          6.0,  'вес, который считается «максимумом»: одинокое место не должно выглядеть как пик'),
  ('min_score',          0.4,  'зоны слабее этого веса не отдаются');

alter table activity_config enable row level security;
create policy activity_config_read
  on activity_config for select to authenticated using (true);

create function city_activity(
  in_lat double precision,
  in_lng double precision,
  in_radius_m integer default 5000,
  in_kinds text[] default array['events', 'places', 'moments'],
  in_categories text[] default null,
  in_at timestamptz default now()
)
returns table (
  latitude     double precision,
  longitude    double precision,
  score        double precision,
  radius_m     integer,
  event_count  integer,
  place_count  integer,
  moment_count integer
)
language plpgsql stable security definer set search_path = public as $$
declare
  cfg jsonb;
  center geography := st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography;
  radius double precision := least(greatest(in_radius_m, 300), 20000);
  cell_m double precision;
  spread_m double precision;
  grid double precision;
begin
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into cfg from activity_config;
  cell_m   := coalesce((cfg ->> 'cell_size_m')::double precision, 600);
  spread_m := coalesce((cfg ->> 'spread_m')::double precision, 450);
  -- Сетка в веб-меркаторе растянута по широте: подгоняем шаг под метры.
  grid := cell_m / cos(radians(in_lat));

  return query
  with objs as (
    select 'e'::text as k, pl.geo as geo,
           coalesce((cfg ->> 'w_event')::double precision, 3)
             * (1 + coalesce((cfg ->> 'w_participant')::double precision, 0.15)
                    * least(coalesce(pc.n, 0), 50))
             * power(0.5, t.dt_h / coalesce((cfg ->> 'half_life_event_h')::double precision, 3)) as w
    from events e
    join places pl on pl.id = e.place_id
    left join lateral (
      select count(*) as n from event_participants ep where ep.event_id = e.id
    ) pc on true
    cross join lateral (
      select case
        when in_at < e.starts_at
          then (extract(epoch from (e.starts_at - in_at)) / 3600.0)::double precision
        when in_at <= coalesce(e.ends_at, e.starts_at + interval '2 hours')
          then 0.0::double precision
        else (extract(epoch from (in_at - coalesce(e.ends_at, e.starts_at + interval '2 hours'))) / 3600.0)::double precision
      end as dt_h
    ) t
    where 'events' = any(in_kinds)
      and e.status = 'active'
      and st_dwithin(pl.geo, center, radius)
      and (in_categories is null or pl.category = any(in_categories))
      and not is_hidden_between(auth.uid(), e.author_id)
      and (case when in_at < e.starts_at
                then t.dt_h <= coalesce((cfg ->> 'event_horizon_h')::double precision, 12)
                else t.dt_h <= coalesce((cfg ->> 'event_past_h')::double precision, 2) end)

    union all

    select 'm'::text, pl.geo,
           coalesce((cfg ->> 'w_moment')::double precision, 1.5)
             * power(0.5, a.age_h / coalesce((cfg ->> 'half_life_moment_h')::double precision, 6))
    from posts p
    join places pl on pl.id = p.place_id
    cross join lateral (
      select (extract(epoch from (in_at - p.created_at)) / 3600.0)::double precision as age_h
    ) a
    where 'moments' = any(in_kinds)
      and p.status = 'active'
      and p.visibility = 'public'
      and p.show_geo
      and a.age_h between 0 and coalesce((cfg ->> 'moment_max_age_h')::double precision, 36)
      and st_dwithin(pl.geo, center, radius)
      and (in_categories is null or pl.category = any(in_categories))
      and not is_hidden_between(auth.uid(), p.author_id)

    union all

    select 'p'::text, pl.geo, coalesce((cfg ->> 'w_place')::double precision, 0.6)
    from places pl
    where 'places' = any(in_kinds)
      and st_dwithin(pl.geo, center, radius)
      and (in_categories is null or pl.category = any(in_categories))
  ),
  cells as (
    select o.k, o.w, o.geo,
           st_x(st_snaptogrid(st_transform(o.geo::geometry, 3857), grid)) as cx,
           st_y(st_snaptogrid(st_transform(o.geo::geometry, 3857), grid)) as cy
    from objs o
  ),
  cnt as (
    select c.cx, c.cy,
           (count(*) filter (where c.k = 'e'))::integer as ec,
           (count(*) filter (where c.k = 'p'))::integer as pc,
           (count(*) filter (where c.k = 'm'))::integer as mc
    from cells c
    group by c.cx, c.cy
  ),
  centers as (
    select cnt.cx, cnt.cy,
           st_transform(st_setsrid(st_makepoint(cnt.cx, cnt.cy), 3857), 4326)::geography as cg
    from cnt
  ),
  scored as (
    select ce.cx, ce.cy, ce.cg,
           sum(o.w * exp(-power(st_distance(ce.cg, o.geo) / spread_m, 2))) as raw
    from centers ce
    join cells o on st_dwithin(ce.cg, o.geo, spread_m * 2.5)
    group by ce.cx, ce.cy, ce.cg
  ),
  peak as (select coalesce(max(s.raw), 0) as m from scored s)
  select st_y(s.cg::geometry),
         st_x(s.cg::geometry),
         least(1.0, s.raw / greatest(peak.m, coalesce((cfg ->> 'ref_score')::double precision, 6)))::double precision,
         cell_m::integer,
         cnt.ec, cnt.pc, cnt.mc
  from scored s
  join cnt on cnt.cx = s.cx and cnt.cy = s.cy
  cross join peak
  where s.raw >= coalesce((cfg ->> 'min_score')::double precision, 0.4)
  order by s.raw desc
  limit 300;
end;
$$;

revoke all on function city_activity from public;
grant execute on function city_activity to authenticated;

-- Место по id — для ссылок и страницы места, когда оно не попало в выборку
-- «рядом». Координаты отдельными колонками: PostgREST иначе отдаёт geography
-- сырым hex EWKB (см. 0011).
create function place_by_id(in_place uuid)
returns table (
  id          uuid,
  title       text,
  description text,
  category    text,
  latitude    double precision,
  longitude   double precision
)
language sql stable security definer set search_path = public as $$
  select p.id, p.title, p.description, p.category,
         st_y(p.geo::geometry), st_x(p.geo::geometry)
  from places p
  where p.id = in_place;
$$;

revoke all on function place_by_id from public;
grant execute on function place_by_id to authenticated;