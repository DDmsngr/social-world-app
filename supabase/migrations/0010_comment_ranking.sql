-- Комментарии ранжируются по лайкам, а не по времени.
--
-- В 0009 порядок внутри каждой ветки задавал таймстамп (path из -epoch у
-- корня и epoch у ответов). Теперь на каждом уровне сначала идёт то, что
-- больше лайкнули — как «Лучшие» на Reddit, а не «Новые». При равном числе
-- лайков (типично для только что написанных комментариев без единого голоса)
-- решает свежесть — иначе куча нулевых комментариев легла бы в порядке
-- выдачи БД, а не понятном человеку.
--
-- Возвращаемая таблица не меняется, поэтому это create or replace, а не
-- drop + create, как в 0006/0009 для city_feed.

create or replace function post_comments_tree(in_post uuid, in_limit integer default 300)
returns table (
  id          uuid,
  parent_id   uuid,
  author_id   uuid,
  author_name text,
  avatar_url  text,
  body        text,
  media_urls  text[],
  created_at  timestamptz,
  deleted     boolean,
  depth       integer,
  like_count  bigint,
  liked_by_me boolean
)
language sql stable security definer set search_path = public as $$
  with recursive likes as (
    select comment_id, count(*)::double precision as n
    from comment_likes
    group by comment_id
  ), tree as (
    select c.id,
           c.parent_id,
           c.author_id,
           c.body,
           c.media_urls,
           c.created_at,
           c.deleted_at,
           0 as depth,
           array[
             -coalesce(l.n, 0),
             -extract(epoch from c.created_at)
           ]::double precision[] as path
    from post_comments c
    left join likes l on l.comment_id = c.id
    where c.post_id = in_post
      and c.parent_id is null
      and c.status <> 'blocked'

    union all

    select c.id,
           c.parent_id,
           c.author_id,
           c.body,
           c.media_urls,
           c.created_at,
           c.deleted_at,
           t.depth + 1,
           t.path || array[
             -coalesce(l.n, 0),
             -extract(epoch from c.created_at)
           ]::double precision[]
    from post_comments c
    join tree t on c.parent_id = t.id
    left join likes l on l.comment_id = c.id
    where c.status <> 'blocked'
  )
  select t.id,
         t.parent_id,
         t.author_id,
         pr.display_name,
         pr.avatar_url,
         case when t.deleted_at is null then t.body else null end,
         case when t.deleted_at is null then t.media_urls else '{}'::text[] end,
         t.created_at,
         t.deleted_at is not null,
         t.depth,
         count(l.profile_id),
         bool_or(l.profile_id = auth.uid())
  from tree t
  join profiles pr on pr.id = t.author_id
  left join comment_likes l on l.comment_id = t.id
  where pr.status <> 'blocked'
  group by t.id, t.parent_id, t.author_id, pr.display_name, pr.avatar_url,
           t.body, t.media_urls, t.created_at, t.deleted_at, t.depth, t.path
  order by t.path
  limit least(in_limit, 500);
$$;
