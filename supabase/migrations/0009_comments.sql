-- Комментарии ветками, как на Reddit.
--
-- Три решения, которые тут заложены:
--   1. Ветвление — через parent_id на саму себя. Глубина не хранится: её
--      считает рекурсивный обход в post_comments_tree, иначе при переносе
--      ветки пришлось бы пересчитывать поддерево.
--   2. Удаление автором — мягкое (deleted_at). Жёсткое удаление унесло бы с
--      собой ответы других людей, и разговор рассыпался бы в середине.
--      Узел остаётся в дереве как «комментарий удалён».
--   3. media_urls заведён сразу, хотя прикреплять фото и гифки к комментариям
--      UI пока не даёт: колонку потом добавить дёшево, а вот переписывать
--      готовый RPC и клиентскую модель — нет.

create table post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references posts on delete cascade,
  parent_id  uuid references post_comments on delete cascade,
  author_id  uuid not null references profiles on delete cascade,
  body       text not null check (length(body) between 1 and 2000),
  media_urls text[] not null default '{}',
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  status     moderation_status not null default 'active'
);

create index post_comments_post_idx on post_comments (post_id, created_at);
create index post_comments_parent_idx on post_comments (parent_id);

alter table post_comments enable row level security;

create policy "комментарии видны всем авторизованным"
  on post_comments for select to authenticated
  using (status <> 'blocked');

create policy "пишу комментарий только от себя"
  on post_comments for insert to authenticated
  with check (auth.uid() = author_id);

-- Удаление автором делается апдейтом deleted_at, поэтому update нужен, но
-- только на свою строку.
create policy "правлю только свой комментарий"
  on post_comments for update to authenticated
  using (auth.uid() = author_id) with check (auth.uid() = author_id);

-- ── голоса ──────────────────────────────────────────────────────────────────
-- Без счётчика «как на Reddit» не получается: по нему потом сортируются ветки.

create table comment_likes (
  comment_id uuid not null references post_comments on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, profile_id)
);

create index comment_likes_comment_idx on comment_likes (comment_id);

alter table comment_likes enable row level security;

create policy "голоса за комментарии видны всем авторизованным"
  on comment_likes for select to authenticated using (true);

create policy "голосую за комментарий только от себя"
  on comment_likes for insert to authenticated
  with check (auth.uid() = profile_id);

create policy "снимаю только свой голос за комментарий"
  on comment_likes for delete to authenticated
  using (auth.uid() = profile_id);

-- Репутация — автору комментария, себе не начисляется: та же логика, что у
-- лайков постов в 0002.
create function apply_comment_like_score() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  target_author uuid;
begin
  if tg_op = 'INSERT' then
    select author_id into target_author from post_comments where id = new.comment_id;
    if target_author is not null and target_author <> new.profile_id then
      insert into score_events (profile_id, reason, delta)
      values (target_author, 'comment_like', 1);
    end if;
    return new;
  end if;

  select author_id into target_author from post_comments where id = old.comment_id;
  if target_author is not null and target_author <> old.profile_id then
    insert into score_events (profile_id, reason, delta)
    values (target_author, 'comment_like', -1);
  end if;
  return old;
end;
$$;

create trigger on_comment_like
  after insert or delete on comment_likes
  for each row execute function apply_comment_like_score();

-- ── дерево ──────────────────────────────────────────────────────────────────
-- Клиенту отдаётся плоский список уже в нужном порядке: собирать дерево на
-- телефоне не нужно, достаточно отрисовать отступ по depth.
--
-- Порядок задаёт path: у корневых веток ключ отрицательный (свежие сверху,
-- как в ленте), у ответов — обычный (разговор читается сверху вниз).

create function post_comments_tree(in_post uuid, in_limit integer default 300)
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
  with recursive tree as (
    select c.id,
           c.parent_id,
           c.author_id,
           c.body,
           c.media_urls,
           c.created_at,
           c.deleted_at,
           0 as depth,
           array[-extract(epoch from c.created_at)]::double precision[] as path
    from post_comments c
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
           t.path || extract(epoch from c.created_at)::double precision
    from post_comments c
    join tree t on c.parent_id = t.id
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

revoke all on function post_comments_tree from public;
grant execute on function post_comments_tree to authenticated;

-- ── лента ───────────────────────────────────────────────────────────────────
-- Карточке нужен счётчик комментариев, иначе кнопка «обсудить» молчит о том,
-- есть ли там разговор. Тип возвращаемой таблицы меняется, поэтому функция
-- пересоздаётся целиком.

drop function city_feed(uuid, integer);

create function city_feed(
  in_author uuid default null,
  in_limit integer default 50
)
returns table (
  id            uuid,
  author_id     uuid,
  author_name   text,
  avatar_url    text,
  kind          post_kind,
  body          text,
  media_urls    text[],
  place_title   text,
  route_id      uuid,
  created_at    timestamptz,
  like_count    bigint,
  liked_by_me   boolean,
  comment_count bigint
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
         count(distinct l.profile_id),
         bool_or(l.profile_id = auth.uid()),
         count(distinct c.id)
  from posts p
  join profiles pr on pr.id = p.author_id
  left join places pl on pl.id = p.place_id
  left join post_likes l on l.post_id = p.id
  left join post_comments c on c.post_id = p.id and c.status <> 'blocked'
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
