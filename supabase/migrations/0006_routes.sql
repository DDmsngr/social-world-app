-- Маршруты: пользователь записывает свой путь по городу, крепит на него фото
-- и публикует в ленту.
--
-- Важно про приватность: в 0001 заложен принцип «точные координаты не покидают
-- устройство» — он про пассивное присутствие (таблица locations, кто рядом).
-- Маршрут устроен наоборот: это контент, который человек осознанно публикует,
-- как фотографию с подписью. Поэтому здесь точная геометрия нужна и хранится,
-- но попадает в базу только по явной команде «опубликовать», а не фоном.

create table routes (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references profiles on delete cascade,
  title       text not null,
  path        geography(linestring, 4326) not null,
  distance_m  integer not null default 0 check (distance_m >= 0),
  duration_s  integer not null default 0 check (duration_s >= 0),
  started_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  status      moderation_status not null default 'active'
);

create index routes_author_idx on routes (author_id);
create index routes_created_idx on routes (created_at desc);

alter table routes enable row level security;

create policy "маршруты видны всем авторизованным"
  on routes for select to authenticated
  using (status <> 'blocked');

create policy "публикую только свой маршрут"
  on routes for insert to authenticated
  with check (auth.uid() = author_id);

create policy "маршрут удаляет автор"
  on routes for delete to authenticated
  using (auth.uid() = author_id);

-- Фото на маршруте: точка съёмки нужна, чтобы поставить метку на линии.
create table route_photos (
  id        uuid primary key default gen_random_uuid(),
  route_id  uuid not null references routes on delete cascade,
  photo_url text not null,
  geo       geography(point, 4326) not null,
  taken_at  timestamptz not null,
  caption   text
);

create index route_photos_route_idx on route_photos (route_id);

alter table route_photos enable row level security;

create policy "фото маршрута видны вместе с маршрутом"
  on route_photos for select to authenticated
  using (exists (
    select 1 from routes r
    where r.id = route_id and r.status <> 'blocked'
  ));

create policy "фото креплю только на свой маршрут"
  on route_photos for insert to authenticated
  with check (exists (
    select 1 from routes r
    where r.id = route_id and r.author_id = auth.uid()
  ));

create policy "фото маршрута удаляет автор"
  on route_photos for delete to authenticated
  using (exists (
    select 1 from routes r
    where r.id = route_id and r.author_id = auth.uid()
  ));

-- Пост-обёртка: маршрут шарится через обычную ленту, чтобы не городить второй
-- социальный контур с лайками и жалобами. Тип поста намеренно не трогаем —
-- ALTER TYPE ... ADD VALUE нельзя использовать в той же транзакции, где это
-- значение уже читают, а наличие route_id и так однозначно опознаёт маршрут.
alter table posts add column route_id uuid references routes on delete cascade;

-- Лента должна отдавать route_id, иначе карточка маршрута в ленте не соберётся.
-- Тип возвращаемой таблицы меняется, а CREATE OR REPLACE так не умеет.
drop function city_feed(uuid, integer);

create function city_feed(
  in_author uuid default null,
  in_limit integer default 50
)
returns table (
  id           uuid,
  author_id    uuid,
  author_name  text,
  avatar_url   text,
  kind         post_kind,
  body         text,
  media_urls   text[],
  place_title  text,
  route_id     uuid,
  created_at   timestamptz,
  like_count   bigint,
  liked_by_me  boolean
)
language sql stable security definer set search_path = public as $$
  select p.id,
         p.author_id,
         pr.display_name,
         pr.avatar_url,
         p.kind,
         p.body,
         p.media_urls,
         pl.title,
         p.route_id,
         p.created_at,
         count(l.profile_id),
         bool_or(l.profile_id = auth.uid())
  from posts p
  join profiles pr on pr.id = p.author_id
  left join places pl on pl.id = p.place_id
  left join post_likes l on l.post_id = p.id
  where p.status = 'active'
    and pr.status <> 'blocked'
    and (in_author is null or p.author_id = in_author)
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and (
          (r.target = 'post' and r.target_id = p.id) or
          (r.target = 'profile' and r.target_id = p.author_id)
        )
    )
  group by p.id, pr.display_name, pr.avatar_url, pl.title
  order by p.created_at desc
  limit least(in_limit, 100);
$$;

revoke all on function city_feed from public;
grant execute on function city_feed to authenticated;

-- Маршрут целиком: линия и фото одним запросом. Геометрия отдаётся как GeoJSON,
-- потому что клиенту всё равно нужен список точек, а не WKB.
create function route_detail(in_route uuid)
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
    and pr.status <> 'blocked';
$$;

revoke all on function route_detail from public;
grant execute on function route_detail to authenticated;

-- Отдельного списка «мои маршруты» здесь нет намеренно: маршрут публикуется
-- постом, а список постов автора уже отдаёт city_feed(in_author) — второй
-- источник той же правды пришлось бы держать синхронным без всякой пользы.

-- ── хранилище фотографий ────────────────────────────────────────────────────
-- Бакет публичный на чтение: фото маршрута и так виден всем, кто видит сам
-- маршрут, а подписанные ссылки в ленте пришлось бы перевыпускать на каждый
-- скролл. Запись — только в свою папку `<uid>/...`.

insert into storage.buckets (id, name, public)
values ('route-photos', 'route-photos', true)
on conflict (id) do nothing;

create policy "фото маршрутов читают все"
  on storage.objects for select
  using (bucket_id = 'route-photos');

-- Имена политик держим короче 63 байт: Postgres режет идентификаторы по этой
-- границе, а в кириллице это всего 31 символ — обрезанные имена разных политик
-- легко совпадают, и создание падает с «policy already exists».
create policy "фото маршрута в свою папку"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'route-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "удаляю только свои фото"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'route-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
