-- Хэштеги и лента «Для вас».
--
-- 1. Хэштеги. Пишутся прямо в тексте (#закат, #спб). Триггер на posts
--    вынимает их из заголовка и текста в post_hashtags — по ней работает
--    лента тега и «популярное». Таблица служебная: клиент читает её только
--    через функции, видимость постов проверяет city_feed.
-- 2. city_feed получает необязательный in_tag. Старые сборки зовут её без
--    него — работают как раньше.
-- 3. for_you_feed — первая версия рекомендаций. Кандидаты — свежие видимые
--    посты (из city_feed), каждому считается вес:
--      подписка на автора                  +3
--      совпадение тегов с моими интересами +1 за тег (до +4)
--      лайки и комментарии                 ln(1+n), комментарии весомее
--      тот же город                        +0.5
--      уже лайкнут мной                    ×0.3 (видел)
--    и всё это гаснет со временем: × exp(−возраст_часов / 72).
--    «Мои интересы» — теги постов, которые я лайкал, комментировал или
--    писал сам за 90 дней. Веса — константы в одном месте, их проще крутить,
--    чем переписывать алгоритм.

-- ── хэштеги ─────────────────────────────────────────────────────────────────

create table post_hashtags (
  post_id    uuid not null references posts on delete cascade,
  tag        text not null check (char_length(tag) between 2 and 50),
  created_at timestamptz not null default now(),
  primary key (post_id, tag)
);
create index post_hashtags_tag_idx on post_hashtags (tag, created_at desc);

alter table post_hashtags enable row level security;
revoke all on post_hashtags from public, anon, authenticated;

-- Теги из текста: буквы любого алфавита, цифры и «_», 2–50 знаков, без
-- повторов, в нижнем регистре, не больше 30 на пост.
create function extract_hashtags(in_text text) returns text[]
language sql immutable set search_path = public as $$
  select coalesce(array_agg(tag), '{}')
  from (
    select distinct lower(m[1]) as tag
    from regexp_matches(coalesce(in_text, ''), '#([[:alnum:]_]{2,50})', 'g') as m
    limit 30
  ) t;
$$;

create function trg_post_hashtags() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from post_hashtags where post_id = new.id;
  insert into post_hashtags (post_id, tag, created_at)
  select new.id, t, new.created_at
  from unnest(extract_hashtags(coalesce(new.title, '') || ' ' || coalesce(new.body, ''))) t
  on conflict do nothing;
  return null;
end;
$$;

create trigger post_hashtags_sync
  after insert or update of body, title on posts
  for each row execute function trg_post_hashtags();

revoke all on function extract_hashtags(text), trg_post_hashtags() from public;

-- Уже написанные посты.
insert into post_hashtags (post_id, tag, created_at)
select p.id, t, p.created_at
from posts p, unnest(extract_hashtags(coalesce(p.title, '') || ' ' || coalesce(p.body, ''))) t
on conflict do nothing;

-- ── лента: фильтр по тегу ───────────────────────────────────────────────────
-- Тело — из 0024, добавлен только in_tag.

drop function city_feed(uuid, integer, uuid, text);

create function city_feed(
  in_author uuid default null,
  in_limit integer default 50,
  in_post uuid default null,
  in_city text default null,
  in_tag text default null
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
    and (in_tag is null or exists (
      select 1 from post_hashtags h
      where h.post_id = p.id and h.tag = lower(ltrim(trim(in_tag), '#'))
    ))
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

-- ── популярные теги и подсказки ─────────────────────────────────────────────

-- Сколько видимых всем постов с тегом за последние in_days дней.
create function trending_hashtags(in_limit integer default 20, in_days integer default 7)
returns table (tag text, posts bigint)
language sql stable security definer set search_path = public as $$
  select h.tag, count(*)
  from post_hashtags h
  join posts p on p.id = h.post_id
  where p.status = 'active'
    and p.visibility = 'public'
    and h.created_at > now() - make_interval(days => least(greatest(in_days, 1), 90))
  group by h.tag
  order by count(*) desc, h.tag
  limit least(greatest(in_limit, 1), 50);
$$;

-- Подсказка при наборе: теги, начинающиеся с введённого.
create function search_hashtags(in_prefix text, in_limit integer default 10)
returns table (tag text, posts bigint)
language sql stable security definer set search_path = public as $$
  select h.tag, count(*)
  from post_hashtags h
  join posts p on p.id = h.post_id
  where p.status = 'active'
    and p.visibility = 'public'
    and h.tag like lower(ltrim(trim(in_prefix), '#')) || '%'
    and char_length(ltrim(trim(in_prefix), '#')) >= 1
  group by h.tag
  order by count(*) desc, h.tag
  limit least(greatest(in_limit, 1), 30);
$$;

revoke all on function trending_hashtags(integer, integer), search_hashtags(text, integer) from public, anon;
grant execute on function trending_hashtags(integer, integer), search_hashtags(text, integer) to authenticated;

-- ── «Для вас» ───────────────────────────────────────────────────────────────

create function for_you_feed(in_limit integer default 50)
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
  comment_count   bigint,
  score           double precision
)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id,
           (select lower(trim(city)) from profiles where profiles.id = auth.uid()) as city
  ),
  -- Мои интересы: теги того, что я лайкал (вес 1), комментировал (2) и писал (2).
  interests as (
    select h.tag, sum(w) as weight
    from (
      select l.post_id, 1.0 as w from post_likes l, me
      where l.profile_id = me.id and l.created_at > now() - interval '90 days'
      union all
      select c.post_id, 2.0 from post_comments c, me
      where c.author_id = me.id and c.created_at > now() - interval '90 days'
      union all
      select p.id, 2.0 from posts p, me
      where p.author_id = me.id and p.created_at > now() - interval '90 days'
    ) s
    join post_hashtags h on h.post_id = s.post_id
    group by h.tag
  ),
  candidates as (
    select f.* from city_feed(in_limit => 100) f
  ),
  scored as (
    select c.*,
      (
        1.0
        + case when exists (
            select 1 from follows fo, me
            where fo.follower_id = me.id
              and fo.target_type = 'profile'
              and fo.target_id = c.author_id
          ) then 3.0 else 0 end
        + least(4.0, coalesce((
            select sum(least(i.weight, 3.0) / 3.0)
            from post_hashtags h join interests i on i.tag = h.tag
            where h.post_id = c.id
          ), 0))
        + 0.7 * ln(1 + c.like_count)
        + 0.9 * ln(1 + c.comment_count)
        + case when (select city from me) is not null
                 and (select lower(trim(pr.city)) from profiles pr where pr.id = c.author_id)
                     = (select city from me)
               then 0.5 else 0 end
      )
      * case when c.liked_by_me then 0.3 else 1.0 end
      * exp(-greatest(extract(epoch from now() - c.created_at), 0) / 3600.0 / 72.0)
      as score
    from candidates c
  )
  select * from scored
  order by score desc, created_at desc
  limit least(greatest(in_limit, 1), 100);
$$;

revoke all on function for_you_feed(integer) from public, anon;
grant execute on function for_you_feed(integer) to authenticated;
