-- Лента «Моменты»: переключатель «Страна | Город» (ТЗ ChaWo, п. 47).
--
-- «Город» — моменты людей, у которых в профиле указан этот город
-- (profiles.city). Параметр необязательный: без него лента та же, что и
-- раньше («Страна»), так что старые сборки приложения продолжают работать.
--
-- Тело — из 0015 без изменений, добавлен только фильтр in_city.

drop function city_feed(uuid, integer, uuid);

create function city_feed(
  in_author uuid default null,
  in_limit integer default 50,
  in_post uuid default null,
  in_city text default null
)
returns table (
  id              uuid,
  author_id       uuid,
  author_name     text,
  avatar_url      text,
  kind            post_kind,
  post_type       text,
  title           text,
  body            text,
  body_format     text,
  visibility      text,
  show_geo        boolean,
  media_urls      text[],
  place_id        uuid,
  place_title     text,
  place_latitude  double precision,
  place_longitude double precision,
  route_id        uuid,
  created_at      timestamptz,
  edited_at       timestamptz,
  like_count      bigint,
  liked_by_me     boolean,
  comment_count   bigint
)
language sql stable security definer set search_path = public as $$
  select p.id,
         p.author_id,
         pr.display_name,
         pr.avatar_url,
         p.kind,
         p.post_type,
         p.title,
         p.body,
         p.body_format,
         p.visibility,
         p.show_geo,
         p.media_urls,
         case when p.show_geo or p.author_id = auth.uid() then pl.id end,
         case when p.show_geo or p.author_id = auth.uid() then pl.title end,
         case when p.show_geo or p.author_id = auth.uid()
              then st_y(pl.geo::geometry) end,
         case when p.show_geo or p.author_id = auth.uid()
              then st_x(pl.geo::geometry) end,
         p.route_id,
         p.created_at,
         p.edited_at,
         count(distinct l.profile_id),
         coalesce(bool_or(l.profile_id = auth.uid()), false),
         count(distinct c.id)
  from posts p
  join profiles pr on pr.id = p.author_id
  left join places pl on pl.id = p.place_id
  left join post_likes l on l.post_id = p.id
  left join post_comments c on c.post_id = p.id and c.status <> 'blocked'
  where p.status = 'active'
    and pr.status <> 'blocked'
    and (in_author is null or p.author_id = in_author)
    and (in_post is null or p.id = in_post)
    and (in_city is null or lower(trim(pr.city)) = lower(trim(in_city)))
    and can_see_post(p.author_id, p.visibility)
    and not is_hidden_between(auth.uid(), p.author_id)
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and (
          (r.target = 'post' and r.target_id = p.id) or
          (r.target = 'profile' and r.target_id = p.author_id)
        )
    )
  group by p.id, pr.id, pl.id
  order by p.created_at desc
  limit least(in_limit, 100);
$$;

revoke all on function city_feed from public;
grant execute on function city_feed to authenticated;
