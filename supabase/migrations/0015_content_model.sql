-- Модель контента: форматы публикаций, видимость, права автора, профили,
-- подписки, блокировки, «Сохранённое», защита от спама.
--
-- Принцип: права проверяет база, а не только интерфейс. Скрытая в UI кнопка
-- «Редактировать» ничего не защищает — защищают RLS, права на колонки и
-- функции ниже.
--
-- Имена новых политик и функций — латиницей: длинные кириллические
-- идентификаторы (>63 байт) Postgres молча обрезает, а через консоль Windows
-- они ещё и перекодируются (см. заметку в памяти проекта о миграции 0008).

-- ── вспомогательные функции доступа ─────────────────────────────────────────

create table user_blocks (
  blocker_id uuid not null references profiles on delete cascade,
  blocked_id uuid not null references profiles on delete cascade,
  -- block: обе стороны друг друга не видят; mute: я не вижу его, он меня видит.
  kind       text not null default 'block' check (kind in ('block', 'mute')),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table user_blocks enable row level security;

create policy user_blocks_select_own
  on user_blocks for select to authenticated using (blocker_id = auth.uid());

-- Записи в user_blocks — только через set_user_block/clear_user_block: при
-- блокировке надо ещё и разорвать подписки, одним INSERT это не сделать.

create table follows (
  follower_id uuid not null references profiles on delete cascade,
  -- Подписки заложены шире, чем «человек на человека»: место или организатор
  -- добавляются значением target_type без новой таблицы.
  target_type text not null check (target_type in ('profile', 'place')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (follower_id, target_type, target_id),
  check (not (target_type = 'profile' and target_id = follower_id))
);

create index follows_target_idx on follows (target_type, target_id);

alter table follows enable row level security;

create policy follows_select_own
  on follows for select to authenticated using (follower_id = auth.uid());
create policy follows_insert_own
  on follows for insert to authenticated with check (follower_id = auth.uid());
create policy follows_delete_own
  on follows for delete to authenticated using (follower_id = auth.uid());

-- Пара (a смотрит, b автор): true, если a не должен видеть контент b.
create function is_hidden_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_blocks x
    where (x.blocker_id = a and x.blocked_id = b)
       or (x.kind = 'block' and x.blocker_id = b and x.blocked_id = a)
  );
$$;

revoke all on function is_hidden_between from public;
grant execute on function is_hidden_between to authenticated;

-- ── посты: форматы, видимость, редактирование ───────────────────────────────

alter table posts
  add column post_type   text not null default 'moment'
    check (post_type in ('moment', 'article')),
  add column title       text
    check (title is null or char_length(title) between 1 and 160),
  add column body_format text not null default 'plain'
    check (body_format in ('plain', 'markdown')),
  add column visibility  text not null default 'public'
    check (visibility in ('public', 'followers', 'private')),
  add column show_geo    boolean not null default true,
  add column edited_at   timestamptz;

alter table posts
  add constraint posts_body_len check (body is null or char_length(body) <= 20000);

create function can_see_post(in_author uuid, in_visibility text) returns boolean
language sql stable security definer set search_path = public as $$
  select case in_visibility
    when 'public' then true
    when 'private' then in_author = auth.uid()
    when 'followers' then
      in_author = auth.uid()
      or exists (
        select 1 from follows f
        where f.follower_id = auth.uid()
          and f.target_type = 'profile'
          and f.target_id = in_author
      )
    else false
  end;
$$;

revoke all on function can_see_post from public;
grant execute on function can_see_post to authenticated;

-- Старая select-политика (она же под кириллическим именем, точное имя после
-- обрезки неизвестно) заменяется новой: иначе две permissive-политики
-- складываются через OR, и видимость ничего бы не ограничивала.
do $$
declare r record;
begin
  for r in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'posts' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on posts', r.policyname);
  end loop;
end $$;

create policy posts_select_visible
  on posts for select to authenticated
  using (
    status = 'active'
    and can_see_post(author_id, visibility)
    and not is_hidden_between(auth.uid(), author_id)
  );

-- Автор правит только содержание и настройки публикации. Статус (модерация),
-- автор и время создания ему не доступны: иначе заблокированный модератором
-- пост можно было бы вернуть обычным PATCH.
revoke update on posts from authenticated;
grant update (kind, body, title, body_format, media_urls, place_id, visibility, show_geo)
  on posts to authenticated;

create function touch_post_edited() returns trigger
language plpgsql as $$
begin
  if new.body is distinct from old.body
     or new.title is distinct from old.title
     or new.media_urls is distinct from old.media_urls then
    new.edited_at := now();
  end if;
  return new;
end;
$$;

create trigger posts_touch_edited
  before update on posts
  for each row execute function touch_post_edited();

-- Лента. Новые колонки: формат, видимость, место с координатами (только если
-- автор разрешил показывать место или смотрит он сам).
drop function city_feed(uuid, integer);

create function city_feed(
  in_author uuid default null,
  in_limit integer default 50,
  in_post uuid default null
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

-- ── жалобы: на свой контент жаловаться нельзя ───────────────────────────────

create function is_own_report_target(in_target report_target, in_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select case in_target
    when 'post'    then exists (select 1 from posts  where id = in_id and author_id = auth.uid())
    when 'event'   then exists (select 1 from events where id = in_id and author_id = auth.uid())
    when 'profile' then in_id = auth.uid()
    when 'place'   then exists (select 1 from places where id = in_id and created_by = auth.uid())
    else false
  end;
$$;

revoke all on function is_own_report_target from public;
grant execute on function is_own_report_target to authenticated;

do $$
declare r record;
begin
  for r in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'reports' and cmd = 'INSERT'
  loop
    execute format('drop policy %I on reports', r.policyname);
  end loop;
end $$;

create policy reports_insert_foreign_only
  on reports for insert to authenticated
  with check (
    auth.uid() = reporter_id
    and not is_own_report_target(target, target_id)
  );

-- ── профили ─────────────────────────────────────────────────────────────────

alter table profiles
  add constraint profiles_bio_len
    check (bio is null or char_length(bio) <= 300) not valid,
  add constraint profiles_name_len
    check (display_name is null or char_length(display_name) <= 60) not valid;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy avatars_read
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy avatars_insert_own_folder
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_delete_own_folder
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Карточка профиля одним запросом: то, что видно другим, и мои отношения с
-- этим человеком. Заблокировавший меня профиль не отдаётся вовсе.
create function profile_card(in_profile uuid)
returns table (
  id              uuid,
  display_name    text,
  avatar_url      text,
  bio             text,
  city            text,
  social_score    integer,
  follower_count  bigint,
  following_count bigint,
  followed_by_me  boolean,
  block_kind      text
)
language sql stable security definer set search_path = public as $$
  select p.id,
         p.display_name,
         p.avatar_url,
         p.bio,
         p.city,
         p.social_score,
         (select count(*) from follows f
           where f.target_type = 'profile' and f.target_id = p.id),
         (select count(*) from follows f
           where f.follower_id = p.id and f.target_type = 'profile'),
         exists (select 1 from follows f
                  where f.follower_id = auth.uid()
                    and f.target_type = 'profile' and f.target_id = p.id),
         (select b.kind from user_blocks b
           where b.blocker_id = auth.uid() and b.blocked_id = p.id)
  from profiles p
  where p.id = in_profile
    and p.status <> 'blocked'
    and not exists (
      select 1 from user_blocks b
      where b.blocker_id = p.id and b.blocked_id = auth.uid() and b.kind = 'block'
    );
$$;

revoke all on function profile_card from public;
grant execute on function profile_card to authenticated;

create function search_profiles(in_query text, in_limit integer default 10)
returns table (id uuid, display_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url
  from profiles p
  where char_length(trim(in_query)) >= 2
    and p.status <> 'blocked'
    and p.id <> auth.uid()
    and p.display_name ilike
        '%' || replace(replace(trim(in_query), '%', '\%'), '_', '\_') || '%'
    and not is_hidden_between(auth.uid(), p.id)
  order by p.display_name
  limit least(in_limit, 20);
$$;

revoke all on function search_profiles from public;
grant execute on function search_profiles to authenticated;

-- ── блокировки ──────────────────────────────────────────────────────────────

create function set_user_block(in_user uuid, in_kind text default 'block')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if in_user = auth.uid() then raise exception 'cannot block self'; end if;
  if in_kind not in ('block', 'mute') then raise exception 'bad kind'; end if;

  insert into user_blocks (blocker_id, blocked_id, kind)
  values (auth.uid(), in_user, in_kind)
  on conflict (blocker_id, blocked_id) do update set kind = excluded.kind;

  -- Заблокированные не должны оставаться подписанными друг на друга.
  if in_kind = 'block' then
    delete from follows
    where target_type = 'profile'
      and ((follower_id = auth.uid() and target_id = in_user)
        or (follower_id = in_user and target_id = auth.uid()));
  end if;
end;
$$;

create function clear_user_block(in_user uuid) returns void
language sql security definer set search_path = public as $$
  delete from user_blocks where blocker_id = auth.uid() and blocked_id = in_user;
$$;

create function my_blocks()
returns table (user_id uuid, display_name text, avatar_url text, kind text)
language sql stable security definer set search_path = public as $$
  select b.blocked_id, p.display_name, p.avatar_url, b.kind
  from user_blocks b
  join profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

revoke all on function set_user_block, clear_user_block, my_blocks from public;
grant execute on function set_user_block, clear_user_block, my_blocks to authenticated;

-- Кого видно на карте «Рядом»: заблокированные и скрытые исчезают.
create or replace function nearby_profiles(
  in_lat double precision,
  in_lng double precision,
  in_radius_m integer default 3000,
  in_limit integer default 100
)
returns table (
  profile_id   uuid,
  display_name text,
  avatar_url   text,
  latitude     double precision,
  longitude    double precision,
  blur_m       integer
)
language sql stable security definer set search_path = public as $$
  select l.profile_id,
         p.display_name,
         p.avatar_url,
         st_y(l.geo::geometry),
         st_x(l.geo::geometry),
         l.blur_radius_m
  from locations l
  join profiles p on p.id = l.profile_id
  where p.status = 'active'
    and l.profile_id <> auth.uid()
    and l.updated_at > now() - interval '2 hours'
    and not is_hidden_between(auth.uid(), l.profile_id)
    and st_dwithin(
          l.geo,
          st_point(in_lng, in_lat)::geography,
          least(in_radius_m, 10000)
        )
  order by l.geo <-> st_point(in_lng, in_lat)::geography
  limit least(in_limit, 200);
$$;

-- ── «Сохранённое» ───────────────────────────────────────────────────────────

create table saved_items (
  profile_id  uuid not null references profiles on delete cascade,
  target_type text not null check (target_type in ('post', 'event', 'place', 'route')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (profile_id, target_type, target_id)
);

alter table saved_items enable row level security;

create policy saved_select_own
  on saved_items for select to authenticated using (profile_id = auth.uid());
create policy saved_insert_own
  on saved_items for insert to authenticated with check (profile_id = auth.uid());
create policy saved_delete_own
  on saved_items for delete to authenticated using (profile_id = auth.uid());

-- Список с названиями одним запросом. Сохранённое, которое стало недоступно
-- (удалено, скрыто автором), просто выпадает из выдачи.
create function my_saved()
returns table (
  target_type text,
  target_id   uuid,
  title       text,
  subtitle    text,
  saved_at    timestamptz
)
language sql stable security definer set search_path = public as $$
  select s.target_type, s.target_id,
         coalesce(p.title, nullif(left(p.body, 90), ''), 'Публикация'),
         pr.display_name,
         s.created_at
  from saved_items s
  join posts p on s.target_type = 'post' and p.id = s.target_id
  join profiles pr on pr.id = p.author_id
  where s.profile_id = auth.uid()
    and p.status = 'active'
    and can_see_post(p.author_id, p.visibility)
    and not is_hidden_between(auth.uid(), p.author_id)
  union all
  select s.target_type, s.target_id, e.title, pl.title, s.created_at
  from saved_items s
  join events e on s.target_type = 'event' and e.id = s.target_id
  left join places pl on pl.id = e.place_id
  where s.profile_id = auth.uid() and e.status = 'active'
  union all
  select s.target_type, s.target_id, pl.title, pl.category, s.created_at
  from saved_items s
  join places pl on s.target_type = 'place' and pl.id = s.target_id
  where s.profile_id = auth.uid()
  union all
  select s.target_type, s.target_id, r.title, 'Маршрут', s.created_at
  from saved_items s
  join routes r on s.target_type = 'route' and r.id = s.target_id
  where s.profile_id = auth.uid() and r.status <> 'blocked'
  order by 5 desc;
$$;

revoke all on function my_saved from public;
grant execute on function my_saved to authenticated;

-- ── базовая защита от спама ─────────────────────────────────────────────────
-- Один общий триггер: окно в секундах и потолок передаются аргументами, так что
-- поменять лимит — это пересоздать триггер, а не переписывать логику.
-- Настоящий anti-fraud (устройства, репутация) сюда не входит намеренно.

create function enforce_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  owner_col text := tg_argv[0];
  window_s  integer := tg_argv[1]::integer;
  max_n     integer := tg_argv[2]::integer;
  owner_id  uuid := (to_jsonb(new) ->> owner_col)::uuid;
  n         integer;
begin
  execute format(
    'select count(*) from %I where %I = $1 and created_at > now() - make_interval(secs => $2)',
    tg_table_name, owner_col
  ) into n using owner_id, window_s;

  if n >= max_n then
    raise exception 'rate_limit: слишком часто, попробуйте позже'
      using errcode = 'P0001', hint = tg_table_name;
  end if;
  return new;
end;
$$;

create trigger posts_rate_limit before insert on posts
  for each row execute function enforce_rate_limit('author_id', '3600', '30');
create trigger events_rate_limit before insert on events
  for each row execute function enforce_rate_limit('author_id', '3600', '10');
create trigger comments_rate_limit before insert on post_comments
  for each row execute function enforce_rate_limit('author_id', '600', '40');
create trigger reports_rate_limit before insert on reports
  for each row execute function enforce_rate_limit('reporter_id', '3600', '20');
create trigger routes_rate_limit before insert on routes
  for each row execute function enforce_rate_limit('author_id', '3600', '10');
