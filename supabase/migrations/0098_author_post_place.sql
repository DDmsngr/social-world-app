-- Пост виртуального автора о месте получает точку на карте (Алексей,
-- 15.10.2026: «точку на карте ставить, чтобы можно было нажать и сразу в
-- ChaWo открывалась эта точка»).
--
-- В очередь (0091) кладут название места и координаты из источника
-- (Википедия). При выпуске поста место ищется среди уже известных: то же
-- название в пределах 300 м. Нет такого — заводится новое, оно же появляется
-- на карте Pulse в слое мест. Пост ссылается на место через posts.place_id;
-- show_geo у такого поста включён: ленты отдают место только при нём (у живых
-- людей это защита адреса), а здесь место публичное, автор виртуальный.
--
-- attach_author_post_place — то же самое для уже вышедших постов.

alter table author_post_queue
  add column place_title text check (place_title is null or char_length(place_title) between 2 and 120),
  add column place_lat double precision check (place_lat is null or place_lat between -90 and 90),
  add column place_lon double precision check (place_lon is null or place_lon between -180 and 180),
  add constraint author_post_queue_place_complete
    check ((place_title is null) = (place_lat is null) and (place_lat is null) = (place_lon is null));

create function author_place_for(in_title text, in_lat double precision, in_lon double precision, in_author uuid)
returns uuid
language plpgsql security definer set search_path = public, extensions set row_security = off as $$
declare
  point geography := st_setsrid(st_makepoint(in_lon, in_lat), 4326)::geography;
  found uuid;
begin
  select id into found from places
  where lower(title) = lower(btrim(in_title)) and st_dwithin(geo, point, 300)
  order by st_distance(geo, point)
  limit 1;
  if found is null then
    insert into places (title, category, geo, created_by)
    values (btrim(in_title), 'Достопримечательность', point, in_author)
    returning id into found;
  end if;
  return found;
end;
$$;

revoke all on function author_place_for(text, double precision, double precision, uuid) from public, anon, authenticated;

create or replace function author_queue_release() returns integer
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  item record;
  new_post uuid;
  place uuid;
  released integer := 0;
begin
  for item in
    select * from author_post_queue
    where status = 'queued' and publish_at <= now()
    order by publish_at
    for update skip locked
  loop
    if item.publish_at < now() - interval '1 day' then
      update author_post_queue set status = 'skipped' where id = item.id;
      continue;
    end if;
    begin
      place := null;
      if item.place_title is not null then
        place := author_place_for(item.place_title, item.place_lat, item.place_lon, item.author_id);
      end if;
      insert into posts (author_id, kind, post_type, body, body_format, media_urls, visibility, show_geo, place_id)
      values (item.author_id,
              case when cardinality(item.media_urls) > 0 then 'photo'::post_kind else 'text'::post_kind end,
              'moment', item.body, 'plain', item.media_urls, 'public', place is not null, place)
      returning id into new_post;
      update author_post_queue set status = 'published', post_id = new_post, published_at = now()
      where id = item.id;
      released := released + 1;
    exception when others then
      update author_post_queue set status = 'error', error = left(sqlerrm, 300) where id = item.id;
    end;
  end loop;
  return released;
end;
$$;

revoke all on function author_queue_release() from public, anon, authenticated;

-- Уже вышедший пост автора: только посты виртуальных авторов и только из их
-- очереди, чужие посты так не правятся.
create function attach_author_post_place(in_post uuid, in_title text, in_lat double precision, in_lon double precision)
returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  author uuid;
  place uuid;
begin
  select q.author_id into author from author_post_queue q where q.post_id = in_post and q.status = 'published';
  if author is null then
    raise exception 'attach_author_post_place: пост не из очереди авторов';
  end if;
  place := author_place_for(in_title, in_lat, in_lon, author);
  update posts set place_id = place, show_geo = true where id = in_post;
  update author_post_queue set place_title = in_title, place_lat = in_lat, place_lon = in_lon where post_id = in_post;
  return place;
end;
$$;

revoke all on function attach_author_post_place(uuid, text, double precision, double precision) from public, anon, authenticated;
grant execute on function attach_author_post_place(uuid, text, double precision, double precision) to service_role;
