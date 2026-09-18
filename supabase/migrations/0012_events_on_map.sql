-- События на карте: city_events отдаёт координаты места, к которому
-- привязано событие. Своих координат у события нет — только place_id,
-- поэтому точка берётся у places (как nearby_places в 0011, через st_x/st_y:
-- PostgREST иначе отдаёт geography как hex EWKB).
--
-- Меняется набор колонок результата, а create or replace такого не умеет —
-- отсюда drop + create и заново выданные права. Старые клиенты новые
-- колонки просто игнорируют, новые без этой миграции получают null и
-- показывают события только списком.

drop function if exists city_events(integer);

create function city_events(in_limit integer default 50)
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
  place_longitude   double precision
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
         bool_or(ep.profile_id = auth.uid()),
         pl.id,
         st_y(pl.geo::geometry),
         st_x(pl.geo::geometry)
  from events e
  join profiles pr on pr.id = e.author_id
  left join places pl on pl.id = e.place_id
  left join event_participants ep on ep.event_id = e.id
  where e.status = 'active'
    and pr.status <> 'blocked'
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and (
          (r.target = 'event' and r.target_id = e.id) or
          (r.target = 'profile' and r.target_id = e.author_id)
        )
    )
  group by e.id, pr.display_name, pr.avatar_url, pl.id
  order by e.starts_at asc
  limit least(in_limit, 100);
$$;

revoke all on function city_events from public;
grant execute on function city_events to authenticated;
