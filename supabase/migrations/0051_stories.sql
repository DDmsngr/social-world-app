-- 0051: настоящие сторис. Раньше полоса над лентой строилась из свежих постов
-- с фото и своей сущности не имела: удалять и настраивать было нечего.
-- Теперь это отдельная таблица: фото, видео или текст на цветном фоне, живут
-- 24 часа, у каждой своё время показа (3–30 с) и своя видимость.
-- Сторис можно сделать из своего поста любого типа: карточка хранит ссылку на
-- пост и по нажатию открывает его.

create table stories (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references profiles(id) on delete cascade,
  kind         text not null check (kind in ('photo', 'video', 'text')),
  media_url    text,
  body         text check (body is null or char_length(body) <= 500),
  bg           smallint not null default 0 check (bg between 0 and 15),
  duration_sec smallint not null default 5 check (duration_sec between 3 and 30),
  visibility   text not null default 'public' check (visibility in ('public', 'followers')),
  post_id      uuid references posts(id) on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '24 hours',
  check ((kind = 'text') = (media_url is null)),
  check (kind <> 'text' or char_length(btrim(coalesce(body, ''))) > 0)
);

create index stories_author_idx on stories (author_id, created_at desc);
create index stories_expires_idx on stories (expires_at);

create table story_views (
  story_id  uuid not null references stories(id) on delete cascade,
  viewer_id uuid not null references profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

alter table stories enable row level security;
alter table story_views enable row level security;

-- Видна ли мне сторис автора: не заблокирован, публичная или я подписан.
create function story_visible_to_me(in_author uuid, in_visibility text)
returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    in_author = auth.uid()
    or (
      not is_hidden_between(auth.uid(), in_author)
      and (
        in_visibility = 'public'
        or exists (
          select 1 from follows f
          where f.follower_id = auth.uid()
            and f.target_type = 'profile'
            and f.target_id = in_author
        )
      )
    )
  );
$$;

revoke all on function story_visible_to_me(uuid, text) from public, anon;
grant execute on function story_visible_to_me(uuid, text) to authenticated;

create policy stories_select on stories for select to authenticated
  using (expires_at > now() and story_visible_to_me(author_id, visibility));
create policy stories_delete_own on stories for delete to authenticated
  using (author_id = auth.uid());

-- Записи в story_views — только через mark_story_viewed; прямого доступа нет.
revoke all on stories, story_views from anon, public;
revoke all on stories, story_views from authenticated;
grant select, delete on stories to authenticated;

-- ── создание ────────────────────────────────────────────────────────────────

create function create_story(
  in_kind       text,
  in_media_url  text,
  in_body       text,
  in_bg         integer,
  in_duration   integer,
  in_visibility text,
  in_post       uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  sid uuid;
begin
  if me is null then
    raise exception 'Нужна авторизация' using errcode = '28000';
  end if;
  if in_post is not null and not exists (
    select 1 from posts where id = in_post and author_id = me
  ) then
    raise exception 'Сторис можно сделать только из своего поста' using errcode = '42501';
  end if;

  -- Старые истории не копим: свои, истёкшие больше недели назад, чистим.
  delete from stories where author_id = me and expires_at < now() - interval '7 days';

  insert into stories (author_id, kind, media_url, body, bg, duration_sec, visibility, post_id)
  values (
    me, in_kind, in_media_url, nullif(btrim(in_body), ''),
    coalesce(in_bg, 0), coalesce(in_duration, 5), coalesce(in_visibility, 'public'), in_post
  )
  returning id into sid;
  return sid;
end;
$$;

revoke all on function create_story(text, text, text, integer, integer, text, uuid) from public, anon;
grant execute on function create_story(text, text, text, integer, integer, text, uuid) to authenticated;

-- ── лента сторис ────────────────────────────────────────────────────────────
-- Все живые истории, которые мне можно видеть, от старых к новым; группировку
-- по авторам делает клиент. view_count виден только автору.

create function stories_feed()
returns table (
  id           uuid,
  author_id    uuid,
  author_name  text,
  author_avatar text,
  kind         text,
  media_url    text,
  body         text,
  bg           smallint,
  duration_sec smallint,
  post_id      uuid,
  created_at   timestamptz,
  expires_at   timestamptz,
  viewed       boolean,
  view_count   bigint,
  followed     boolean
)
language sql stable security definer set search_path = public as $$
  select
    s.id, s.author_id, pr.display_name, pr.avatar_url,
    s.kind, s.media_url, s.body, s.bg, s.duration_sec, s.post_id,
    s.created_at, s.expires_at,
    exists (select 1 from story_views v where v.story_id = s.id and v.viewer_id = auth.uid()),
    case when s.author_id = auth.uid()
         then (select count(*) from story_views v where v.story_id = s.id) end,
    exists (
      select 1 from follows f
      where f.follower_id = auth.uid() and f.target_type = 'profile' and f.target_id = s.author_id
    )
  from stories s
  join profiles pr on pr.id = s.author_id
  where s.expires_at > now()
    and story_visible_to_me(s.author_id, s.visibility)
  order by s.created_at
  limit 300;
$$;

revoke all on function stories_feed() from public, anon;
grant execute on function stories_feed() to authenticated;

-- ── просмотры ───────────────────────────────────────────────────────────────

create function mark_story_viewed(in_story uuid)
returns void
language sql security definer set search_path = public as $$
  insert into story_views (story_id, viewer_id)
  select s.id, auth.uid()
  from stories s
  where s.id = in_story
    and s.author_id <> auth.uid()
    and s.expires_at > now()
    and story_visible_to_me(s.author_id, s.visibility)
  on conflict do nothing;
$$;

revoke all on function mark_story_viewed(uuid) from public, anon;
grant execute on function mark_story_viewed(uuid) to authenticated;

create function story_viewers(in_story uuid)
returns table (profile_id uuid, display_name text, avatar_url text, viewed_at timestamptz)
language sql stable security definer set search_path = public as $$
  select v.viewer_id, pr.display_name, pr.avatar_url, v.viewed_at
  from story_views v
  join stories s on s.id = v.story_id
  join profiles pr on pr.id = v.viewer_id
  where v.story_id = in_story and s.author_id = auth.uid()
  order by v.viewed_at desc
  limit 200;
$$;

revoke all on function story_viewers(uuid) from public, anon;
grant execute on function story_viewers(uuid) to authenticated;
