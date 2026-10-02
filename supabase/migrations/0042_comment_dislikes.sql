-- Дизлайки комментариев (посты и каналы).
--
-- Голос один на человека: лайк и дизлайк друг друга заменяют. Дерево
-- сортируется по «счёту» (лайки минус дизлайки), а не по одним лайкам.
-- Дизлайк репутацию автора не трогает (в отличие от лайка в 0009): иначе
-- «минусовать» можно было бы ради травли.
--
-- В обоих деревьях добавились колонки dislike_count и disliked_by_me, а у
-- функции с таким возвратом изменить результат нельзя — drop + create и
-- права заново (revoke от public/anon, как в 0027).

-- ── 1. таблицы ──────────────────────────────────────────────────────────────

create table comment_dislikes (
  comment_id uuid not null references post_comments on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, profile_id)
);
create index comment_dislikes_comment_idx on comment_dislikes (comment_id);
alter table comment_dislikes enable row level security;
revoke all on comment_dislikes from public, anon, authenticated;

create table channel_comment_dislikes (
  comment_id uuid not null references channel_comments on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, profile_id)
);
alter table channel_comment_dislikes enable row level security;
revoke all on channel_comment_dislikes from public, anon, authenticated;

-- ── 2. голосование ──────────────────────────────────────────────────────────

create function comment_set_vote(in_comment uuid, in_vote smallint)
returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'authentication required'; end if;
  if in_vote not in (-1, 0, 1) then raise exception 'bad vote'; end if;
  if not exists (
    select 1 from post_comments c where c.id = in_comment and c.status <> 'blocked'
  ) then
    raise exception 'not allowed';
  end if;

  delete from comment_dislikes where comment_id = in_comment and profile_id = me;
  if in_vote = 1 then
    insert into comment_likes (comment_id, profile_id) values (in_comment, me)
    on conflict do nothing;
  else
    delete from comment_likes where comment_id = in_comment and profile_id = me;
  end if;
  if in_vote = -1 then
    insert into comment_dislikes (comment_id, profile_id) values (in_comment, me)
    on conflict do nothing;
  end if;
end;
$$;

create function channel_comment_set_vote(in_comment uuid, in_vote smallint)
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'authentication required'; end if;
  if in_vote not in (-1, 0, 1) then raise exception 'bad vote'; end if;
  if not exists (
    select 1 from channel_comments k
    where k.id = in_comment
      and can_read_channel(channel_comment_message_channel(k.message_id))
  ) then
    raise exception 'not allowed';
  end if;

  delete from channel_comment_dislikes where comment_id = in_comment and profile_id = me;
  if in_vote = 1 then
    insert into channel_comment_likes (comment_id, profile_id) values (in_comment, me)
    on conflict do nothing;
  else
    delete from channel_comment_likes where comment_id = in_comment and profile_id = me;
  end if;
  if in_vote = -1 then
    insert into channel_comment_dislikes (comment_id, profile_id) values (in_comment, me)
    on conflict do nothing;
  end if;
end;
$$;

-- ── 3. деревья с дизлайками ─────────────────────────────────────────────────

drop function post_comments_tree(uuid, integer);
create function post_comments_tree(in_post uuid, in_limit integer default 300)
returns table (
  id uuid, parent_id uuid, author_id uuid, author_name text, avatar_url text,
  body text, media_urls text[], created_at timestamptz, deleted boolean,
  depth integer, like_count bigint, liked_by_me boolean,
  dislike_count bigint, disliked_by_me boolean
)
language sql stable security definer set search_path = public as $$
  with recursive votes as (
    select v.comment_id, sum(v.s)::double precision as n
    from (
      select comment_id, 1 as s from comment_likes
      union all
      select comment_id, -1 as s from comment_dislikes
    ) v
    join post_comments k on k.id = v.comment_id and k.post_id = in_post
    group by v.comment_id
  ), tree as (
    select c.id, c.parent_id, c.author_id, c.body, c.media_urls, c.created_at, c.deleted_at,
           0 as depth,
           array[-coalesce(l.n, 0), -extract(epoch from c.created_at)]::double precision[] as path
    from post_comments c
    left join votes l on l.comment_id = c.id
    where c.post_id = in_post and c.parent_id is null and c.status <> 'blocked'
    union all
    select c.id, c.parent_id, c.author_id, c.body, c.media_urls, c.created_at, c.deleted_at,
           t.depth + 1,
           t.path || array[-coalesce(l.n, 0), -extract(epoch from c.created_at)]::double precision[]
    from post_comments c
    join tree t on c.parent_id = t.id
    left join votes l on l.comment_id = c.id
    where c.status <> 'blocked'
  )
  select t.id, t.parent_id, t.author_id, pr.display_name, pr.avatar_url,
         case when t.deleted_at is null then t.body else null end,
         case when t.deleted_at is null then t.media_urls else '{}'::text[] end,
         t.created_at, t.deleted_at is not null, t.depth,
         (select count(*) from comment_likes l where l.comment_id = t.id),
         exists (select 1 from comment_likes l where l.comment_id = t.id and l.profile_id = auth.uid()),
         (select count(*) from comment_dislikes d where d.comment_id = t.id),
         exists (select 1 from comment_dislikes d where d.comment_id = t.id and d.profile_id = auth.uid())
  from tree t
  join profiles pr on pr.id = t.author_id
  where pr.status <> 'blocked'
  order by t.path
  limit least(in_limit, 500);
$$;

drop function channel_comments_tree(uuid, integer);
create function channel_comments_tree(in_message uuid, in_limit integer default 300)
returns table (
  id uuid, parent_id uuid, author_id uuid, author_name text, avatar_url text,
  body text, media_urls text[], created_at timestamptz, deleted boolean,
  depth integer, like_count bigint, liked_by_me boolean,
  dislike_count bigint, disliked_by_me boolean
)
language sql stable security definer set search_path = public set row_security = off as $$
  with recursive votes as (
    select v.comment_id, sum(v.s)::double precision as n
    from (
      select comment_id, 1 as s from channel_comment_likes
      union all
      select comment_id, -1 as s from channel_comment_dislikes
    ) v
    join channel_comments k on k.id = v.comment_id and k.message_id = in_message
    group by v.comment_id
  ), tree as (
    select c.id, c.parent_id, c.author_id, c.body, c.created_at, c.deleted_at,
           0 as depth,
           array[-coalesce(l.n, 0), -extract(epoch from c.created_at)]::double precision[] as path
    from channel_comments c
    left join votes l on l.comment_id = c.id
    where c.message_id = in_message and c.parent_id is null
    union all
    select c.id, c.parent_id, c.author_id, c.body, c.created_at, c.deleted_at,
           t.depth + 1,
           t.path || array[-coalesce(l.n, 0), -extract(epoch from c.created_at)]::double precision[]
    from channel_comments c
    join tree t on c.parent_id = t.id
    left join votes l on l.comment_id = c.id
  )
  select t.id, t.parent_id, t.author_id, pr.display_name, pr.avatar_url,
         case when t.deleted_at is null then t.body end,
         '{}'::text[],
         t.created_at, t.deleted_at is not null, t.depth,
         (select count(*) from channel_comment_likes l where l.comment_id = t.id),
         exists (select 1 from channel_comment_likes l where l.comment_id = t.id and l.profile_id = auth.uid()),
         (select count(*) from channel_comment_dislikes d where d.comment_id = t.id),
         exists (select 1 from channel_comment_dislikes d where d.comment_id = t.id and d.profile_id = auth.uid())
  from tree t
  join profiles pr on pr.id = t.author_id
  where pr.status <> 'blocked'
    and can_read_channel(channel_comment_message_channel(in_message))
  order by t.path
  limit least(in_limit, 500);
$$;

-- ── 4. права ────────────────────────────────────────────────────────────────

revoke all on function
  comment_set_vote(uuid, smallint),
  channel_comment_set_vote(uuid, smallint),
  post_comments_tree(uuid, integer),
  channel_comments_tree(uuid, integer)
from public, anon;

grant execute on function
  comment_set_vote(uuid, smallint),
  channel_comment_set_vote(uuid, smallint),
  post_comments_tree(uuid, integer),
  channel_comments_tree(uuid, integer)
to authenticated;
