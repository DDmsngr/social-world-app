-- Своя точка на карте у статьи и события.
--
-- Пост и событие хранят только place_id, а все ленты и карта читают место
-- соединением с places. Поэтому свободную точку кладём тем же путём: строка
-- в places с флагом is_custom. В каталог заведений «рядом» такие точки не
-- попадают (это не заведения), но ссылка по id, лента и карта их видят.

alter table places add column if not exists is_custom boolean not null default false;

create index if not exists places_custom_author_idx
  on places (created_by, created_at) where is_custom;

-- Заведения рядом: без чужих свободных точек.
create or replace function nearby_places(
  in_lat double precision,
  in_lng double precision,
  in_radius_m integer default 5000,
  in_limit integer default 200
)
returns table (
  id          uuid,
  title       text,
  description text,
  category    text,
  latitude    double precision,
  longitude   double precision
)
language sql stable security definer set search_path = public as $$
  select p.id,
         p.title,
         p.description,
         p.category,
         st_y(p.geo::geometry),
         st_x(p.geo::geometry)
  from places p
  where not p.is_custom
    and st_dwithin(
      p.geo,
      st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography,
      in_radius_m
    )
  order by p.geo <-> st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography
  limit least(in_limit, 500);
$$;

-- Создаёт свою точку и отдаёт её в том же виде, что place_by_id. Не больше
-- 30 точек в сутки с одного аккаунта.
create function create_custom_place(
  in_title text,
  in_lat double precision,
  in_lng double precision
)
returns table (
  id          uuid,
  title       text,
  description text,
  category    text,
  latitude    double precision,
  longitude   double precision
)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  clean_title text := left(btrim(coalesce(in_title, '')), 120);
  new_id uuid;
  recent integer;
begin
  if uid is null then raise exception 'нужен вход'; end if;
  if in_lat is null or in_lng is null
     or in_lat not between -90 and 90 or in_lng not between -180 and 180 then
    raise exception 'неверные координаты';
  end if;
  if clean_title = '' then clean_title := 'Точка на карте'; end if;

  select count(*) into recent
  from places p
  where p.created_by = uid and p.is_custom and p.created_at > now() - interval '1 day';
  if recent >= 30 then raise exception 'слишком много своих точек за сутки'; end if;

  insert into places (title, category, geo, created_by, is_custom)
  values (
    clean_title,
    'Точка',
    st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography,
    uid,
    true
  )
  returning places.id into new_id;

  return query
  select p.id, p.title, p.description, p.category,
         st_y(p.geo::geometry), st_x(p.geo::geometry)
  from places p
  where p.id = new_id;
end $$;

revoke all on function create_custom_place from public;
grant execute on function create_custom_place to authenticated;
