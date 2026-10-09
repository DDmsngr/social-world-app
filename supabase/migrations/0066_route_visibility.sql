-- Видимость маршрута. Раньше политика пускала к маршруту любого вошедшего, даже
-- если пост-обёртка скрыта: ограничение жило только в ленте. Теперь маршрут
-- несёт видимость сам и проверяется на сервере, как пост.
--
-- visibility: public | followers | private (те же значения, что у постов).
-- link_access: «Никому» в ленте, но по прямой ссылке открывается у любого
-- вошедшего. id маршрута — случайный uuid, перебором не находится.

alter table routes
  add column visibility text not null default 'public'
    check (visibility in ('public', 'followers', 'private')),
  add column link_access boolean not null default false;

create or replace function can_see_route(
  in_author uuid, in_visibility text, in_link boolean
) returns boolean
language sql stable security definer set search_path = public as $$
  select in_author = auth.uid()
      or (
        (in_link or can_see_post(in_author, in_visibility))
        and not is_hidden_between(auth.uid(), in_author)
      );
$$;

revoke all on function can_see_route from public;
grant execute on function can_see_route to authenticated;

-- Имя старой политики обрезано Postgres'ом по 63 байтам и неточно известно,
-- поэтому сносим все select-политики: иначе permissive-политики складываются
-- через OR, и новая ничего бы не ограничила.
do $$
declare r record;
begin
  for r in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'routes' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on routes', r.policyname);
  end loop;
end $$;

create policy routes_select_visible
  on routes for select to authenticated
  using (
    status <> 'blocked'
    and can_see_route(author_id, visibility, link_access)
  );

-- Фото проверяют маршрут через его политику (подзапрос идёт под RLS), отдельно
-- менять их политику не нужно. route_detail — security definer, RLS обходит,
-- поэтому условие повторено в самой функции.
create or replace function route_detail(in_route uuid)
returns table (
  id          uuid,
  author_id   uuid,
  author_name text,
  avatar_url  text,
  title       text,
  path        jsonb,
  distance_m  integer,
  duration_s  integer,
  started_at  timestamptz,
  created_at  timestamptz,
  photos      jsonb
)
language sql stable security definer set search_path = public as $$
  select r.id,
         r.author_id,
         pr.display_name,
         pr.avatar_url,
         r.title,
         st_asgeojson(r.path)::jsonb,
         r.distance_m,
         r.duration_s,
         r.started_at,
         r.created_at,
         coalesce(
           (select jsonb_agg(
                     jsonb_build_object(
                       'id', rp.id,
                       'photo_url', rp.photo_url,
                       'caption', rp.caption,
                       'taken_at', rp.taken_at,
                       'latitude', st_y(rp.geo::geometry),
                       'longitude', st_x(rp.geo::geometry)
                     ) order by rp.taken_at
                   )
              from route_photos rp
             where rp.route_id = r.id),
           '[]'::jsonb
         )
  from routes r
  join profiles pr on pr.id = r.author_id
  where r.id = in_route
    and r.status <> 'blocked'
    and pr.status <> 'blocked'
    and can_see_route(r.author_id, r.visibility, r.link_access);
$$;

revoke all on function route_detail from public;
grant execute on function route_detail to authenticated;
