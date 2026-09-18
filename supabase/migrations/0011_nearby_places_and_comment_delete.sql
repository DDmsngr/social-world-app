-- Два независимых фикса по итогам аудита (Astra), оба подтверждены чтением
-- реального кода/схемы:
--
-- 1. GEO-1: SupabaseDiscoverRepository запрашивал `places.geo` напрямую через
--    PostgREST — тот отдаёт geography как hex EWKB, а не GeoJSON/WKT, поэтому
--    `_readPoint` не распознаёт формат и падает с FormatException при первом
--    же реальном месте. `nearby_profiles` эту же проблему уже решает, отдавая
--    latitude/longitude отдельными колонками — здесь та же схема для мест.
--
-- 2. RLS-1: у `post_comments` select-политика проверяет только status, но не
--    deleted_at — значит текст «удалённого» комментария (body, media_urls)
--    остаётся читаемым прямым REST-запросом к таблице в обход RPC, которая
--    его маскирует. Раз RPC уже не может доверять сырым данным, комментарий
--    надо очищать по-настоящему в момент удаления, а не только помечать.

create function nearby_places(
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
  where st_dwithin(
    p.geo,
    st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography,
    in_radius_m
  )
  order by p.geo <-> st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography
  limit least(in_limit, 500);
$$;

revoke all on function nearby_places from public;
grant execute on function nearby_places to authenticated;

-- Мягкое удаление комментария теперь по-настоящему стирает содержимое, а не
-- только выставляет deleted_at: RPC и так подставляла null поверх, но прямой
-- SELECT к таблице (например, через PostgREST в обход RPC) отдавал исходный
-- текст всем, у кого есть select-доступ к post_comments.
create or replace function soft_delete_own_comment(in_comment uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  -- body: not null + check (length between 1 and 2000) — null или пустая
  -- строка тут же уронят апдейт нарушением ограничения, поэтому вместо
  -- пустого значения кладём плейсхолдер. RPC post_comments_tree всё равно
  -- подменяет его на null на выдаче по deleted_at, реальный текст этот
  -- плейсхолдер никогда не покажет.
  update post_comments
     set deleted_at = now(),
         body = '[комментарий удалён]',
         media_urls = '{}'
   where id = in_comment
     and author_id = auth.uid();
end;
$$;

revoke all on function soft_delete_own_comment from public;
grant execute on function soft_delete_own_comment to authenticated;

-- RLS-3: политика "правлю только свой профиль" ограничивает строку, но не
-- колонки — обычный PATCH на свою же строку мог переписать social_score или
-- status (снять с себя бан) напрямую, в обход score_events и модерации.
-- Column-level GRANT/REVOKE — единственный способ Postgres запретить запись
-- в конкретные колонки при разрешённом UPDATE строки.
revoke update on profiles from authenticated;
grant update (display_name, avatar_url, bio, city, location_blur_m)
  on profiles to authenticated;
