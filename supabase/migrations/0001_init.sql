-- Social World — начальная схема.
--
-- Два принципа, заложенных с первой миграции:
--   1. Точных координат в базе нет. В `locations` пишется только размытая точка
--      и радиус размытия — так требует план и так меньше персональных данных
--      попадает под 152-ФЗ.
--   2. RLS включён на каждой таблице. Политика по умолчанию — «ничего нельзя»,
--      дальше открываем ровно то, что нужно экрану.

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- ── типы ────────────────────────────────────────────────────────────────────

create type post_kind as enum ('photo', 'video', 'short', 'text');
create type report_target as enum ('profile', 'post', 'place', 'event');
create type report_status as enum ('new', 'in_review', 'resolved', 'rejected');
create type moderation_status as enum ('active', 'limited', 'blocked');

-- ── профили ─────────────────────────────────────────────────────────────────

create table profiles (
  id                uuid primary key references auth.users on delete cascade,
  display_name      text,
  avatar_url        text,
  bio               text,
  city              text default 'Сочи',
  social_score      integer not null default 0,
  status            moderation_status not null default 'active',
  -- Радиус, с которым пользователь готов быть виден на карте.
  location_blur_m   integer not null default 500 check (location_blur_m >= 200),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table profiles enable row level security;

create policy "профили видны всем авторизованным"
  on profiles for select to authenticated
  using (status <> 'blocked');

create policy "правлю только свой профиль"
  on profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

create policy "создаю только свой профиль"
  on profiles for insert to authenticated
  with check (auth.uid() = id);

-- Профиль появляется вместе с аккаунтом, чтобы клиенту не приходилось
-- разбираться, есть строка или нет.
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ── места ───────────────────────────────────────────────────────────────────

create table places (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  category    text,
  -- У места координата точная — это публичный объект, не человек.
  geo         geography(point, 4326) not null,
  created_by  uuid references profiles on delete set null,
  created_at  timestamptz not null default now()
);

create index places_geo_idx on places using gist (geo);
alter table places enable row level security;

create policy "места видны всем авторизованным"
  on places for select to authenticated using (true);

create policy "место добавляет автор"
  on places for insert to authenticated with check (auth.uid() = created_by);

-- ── посты ───────────────────────────────────────────────────────────────────

create table posts (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references profiles on delete cascade,
  kind        post_kind not null default 'text',
  body        text,
  media_urls  text[] not null default '{}',
  place_id    uuid references places on delete set null,
  -- Гео поста — тоже размытое: пост из дома не должен выдавать адрес.
  geo         geography(point, 4326),
  blur_m      integer,
  status      moderation_status not null default 'active',
  created_at  timestamptz not null default now()
);

create index posts_author_idx on posts (author_id, created_at desc);
create index posts_geo_idx on posts using gist (geo);
alter table posts enable row level security;

create policy "лента видна всем авторизованным"
  on posts for select to authenticated using (status = 'active');

create policy "пост создаёт автор"
  on posts for insert to authenticated with check (auth.uid() = author_id);

create policy "пост правит автор"
  on posts for update to authenticated
  using (auth.uid() = author_id) with check (auth.uid() = author_id);

create policy "пост удаляет автор"
  on posts for delete to authenticated using (auth.uid() = author_id);

-- ── события ─────────────────────────────────────────────────────────────────

create table events (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references profiles on delete cascade,
  title       text not null,
  description text,
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  place_id    uuid references places on delete set null,
  geo         geography(point, 4326),
  cover_url   text,
  status      moderation_status not null default 'active',
  created_at  timestamptz not null default now()
);

create index events_starts_idx on events (starts_at);
create index events_geo_idx on events using gist (geo);
alter table events enable row level security;

create policy "события видны всем авторизованным"
  on events for select to authenticated using (status = 'active');

create policy "событие создаёт автор"
  on events for insert to authenticated with check (auth.uid() = author_id);

create policy "событие правит автор"
  on events for update to authenticated
  using (auth.uid() = author_id) with check (auth.uid() = author_id);

create table event_participants (
  event_id   uuid not null references events on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (event_id, profile_id)
);

alter table event_participants enable row level security;

create policy "участники видны всем авторизованным"
  on event_participants for select to authenticated using (true);

create policy "записываю на событие только себя"
  on event_participants for insert to authenticated
  with check (auth.uid() = profile_id);

create policy "отписываю от события только себя"
  on event_participants for delete to authenticated
  using (auth.uid() = profile_id);

-- ── геопозиция ──────────────────────────────────────────────────────────────

-- Одна строка на пользователя: историю перемещений не копим — нечего хранить,
-- нечего отдавать, нечего терять.
create table locations (
  profile_id    uuid primary key references profiles on delete cascade,
  geo           geography(point, 4326) not null,
  blur_radius_m integer not null check (blur_radius_m >= 200),
  updated_at    timestamptz not null default now()
);

create index locations_geo_idx on locations using gist (geo);
alter table locations enable row level security;

create policy "свою точку вижу"
  on locations for select to authenticated using (auth.uid() = profile_id);

create policy "свою точку пишу"
  on locations for insert to authenticated with check (auth.uid() = profile_id);

create policy "свою точку обновляю"
  on locations for update to authenticated
  using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

create policy "свою точку удаляю"
  on locations for delete to authenticated using (auth.uid() = profile_id);

-- Чужие точки отдаёт только эта функция — и только те, что уже размыты
-- клиентом. Прямого select по чужим строкам нет.
create function nearby_profiles(
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
    and st_dwithin(
          l.geo,
          st_point(in_lng, in_lat)::geography,
          least(in_radius_m, 10000)
        )
  order by l.geo <-> st_point(in_lng, in_lat)::geography
  limit least(in_limit, 200);
$$;

revoke all on function nearby_profiles from public;
grant execute on function nearby_profiles to authenticated;

-- ── жалобы ──────────────────────────────────────────────────────────────────

create table reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles on delete cascade,
  target      report_target not null,
  target_id   uuid not null,
  reason      text not null,
  comment     text,
  status      report_status not null default 'new',
  created_at  timestamptz not null default now()
);

create index reports_status_idx on reports (status, created_at);
alter table reports enable row level security;

create policy "жалобу пишет любой авторизованный"
  on reports for insert to authenticated with check (auth.uid() = reporter_id);

create policy "вижу только свои жалобы"
  on reports for select to authenticated using (auth.uid() = reporter_id);

-- ── репутация ───────────────────────────────────────────────────────────────

create table score_events (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles on delete cascade,
  reason     text not null,
  delta      integer not null,
  created_at timestamptz not null default now()
);

create index score_events_profile_idx on score_events (profile_id, created_at desc);
alter table score_events enable row level security;

create policy "свой лог репутации вижу"
  on score_events for select to authenticated using (auth.uid() = profile_id);

-- Счётчик в профиле — производная от лога, руками его никто не правит.
create function apply_score_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update profiles
     set social_score = social_score + new.delta,
         updated_at = now()
   where id = new.profile_id;
  return new;
end;
$$;

create trigger on_score_event
  after insert on score_events
  for each row execute function apply_score_event();
