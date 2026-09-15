-- Лента: лайки и запрос, который отдаёт посты сразу с автором и счётчиками.
--
-- Лайк — первое действие, за которое начисляется Social Score. До него счётчик
-- в профиле был декоративным: таблица score_events есть, а писать в неё нечему.

create table post_likes (
  post_id    uuid not null references posts on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);

create index post_likes_post_idx on post_likes (post_id);

alter table post_likes enable row level security;

create policy "лайки видны всем авторизованным"
  on post_likes for select to authenticated using (true);

create policy "ставлю лайк только от себя"
  on post_likes for insert to authenticated
  with check (auth.uid() = profile_id);

create policy "снимаю только свой лайк"
  on post_likes for delete to authenticated
  using (auth.uid() = profile_id);

-- Репутацию получает автор поста, а не тот, кто лайкнул.
-- Себе лайк не засчитывается, иначе счёт накручивается в одну строку.
create function apply_like_score() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  target_author uuid;
  delta integer;
begin
  if tg_op = 'INSERT' then
    select author_id into target_author from posts where id = new.post_id;
    delta := 1;
    if target_author is null or target_author = new.profile_id then
      return new;
    end if;
  else
    select author_id into target_author from posts where id = old.post_id;
    delta := -1;
    if target_author is null or target_author = old.profile_id then
      return old;
    end if;
  end if;

  insert into score_events (profile_id, reason, delta)
  values (target_author, 'like', delta);

  return case tg_op when 'INSERT' then new else old end;
end;
$$;

create trigger on_post_like
  after insert or delete on post_likes
  for each row execute function apply_like_score();

-- Лента одним запросом: пост, автор, место, счётчик лайков и отметка «я лайкнул».
-- Без этого клиенту пришлось бы делать три обращения и склеивать их руками.
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
    -- Контент тех, на кого пожаловался этот пользователь, из ленты уходит
    -- сразу, не дожидаясь разбора жалобы.
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
