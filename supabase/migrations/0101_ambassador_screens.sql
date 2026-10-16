-- Амбассадоры в приложении (шаг 3): что открывается клиенту.
--
-- Рейтинги из 0100 считают журнал AP заново при каждом вызове, поэтому
-- клиенту отдаётся снимок: раз в 10 минут задача пересчитывает топ-50 каждого
-- города за идущий сезон и топ-50 годового конкурса, а экран читает готовые
-- строки. Зал славы и статус для значка — маленькие таблицы, их можно читать
-- напрямую.

create table ambassador_rating_snapshot (
  season_id   integer not null references ambassador_seasons,
  city        text not null references ambassador_cities,
  place       integer not null,
  profile_id  uuid not null references profiles on delete cascade,
  season_ap   bigint not null,
  total_ap    integer not null,
  computed_at timestamptz not null default now(),
  primary key (season_id, city, place)
);

create table ambassador_year_snapshot (
  year        integer not null,
  place       integer not null,
  profile_id  uuid not null references profiles on delete cascade,
  year_ap     bigint not null,
  total_ap    integer not null,
  computed_at timestamptz not null default now(),
  primary key (year, place)
);

alter table ambassador_rating_snapshot enable row level security;
alter table ambassador_year_snapshot enable row level security;
revoke all on ambassador_rating_snapshot, ambassador_year_snapshot from public, anon, authenticated;

-- Год конкурса, который идёт сейчас: с 15.12 начинается следующий.
create function ambassador_current_year() returns integer
language sql stable security definer set search_path = public as $$
  select case
    when now() >= make_timestamptz(extract(year from now() at time zone 'Europe/Moscow')::integer,
                                   12, 15, 0, 0, 0, 'Europe/Moscow')
      then extract(year from now() at time zone 'Europe/Moscow')::integer + 1
    else extract(year from now() at time zone 'Europe/Moscow')::integer
  end
$$;

create function ambassador_snapshot_refresh() returns void
language plpgsql security definer set search_path = public as $$
declare
  cur integer := ambassador_current_season();
  yr integer := ambassador_current_year();
begin
  if cur is not null then
    delete from ambassador_rating_snapshot where season_id = cur;
    insert into ambassador_rating_snapshot (season_id, city, place, profile_id, season_ap, total_ap)
    select cur, c.name, r.place, r.profile_id, r.season_ap, r.total_ap
    from ambassador_cities c
    cross join lateral ambassador_city_rating(cur, c.name, 50) r;
  end if;

  delete from ambassador_year_snapshot where year = yr;
  insert into ambassador_year_snapshot (year, place, profile_id, year_ap, total_ap)
  select yr, r.place, r.profile_id, r.year_ap, r.total_ap
  from ambassador_year_rating(yr, 50) r;
end $$;

-- ── что читает приложение ───────────────────────────────────────────────────

-- Шапка экрана: сезон, мой город, моё место, лидеры городов, порог приза.
create function ambassador_overview() returns jsonb
language sql stable security definer set search_path = public as $$
  with s as (
    select * from ambassador_seasons where id = ambassador_current_season()
  ), my_city as (
    select c.name from profiles p join ambassador_cities c on lower(c.name) = lower(trim(p.city))
    where p.id = auth.uid()
  )
  select jsonb_build_object(
    'season', (select jsonb_build_object('id', id, 'starts_at', starts_at, 'ends_at', ends_at) from s),
    'city', (select name from my_city),
    'me', (select jsonb_build_object('place', r.place, 'season_ap', r.season_ap)
           from ambassador_rating_snapshot r, s
           where r.season_id = s.id and r.profile_id = auth.uid() and r.city = (select name from my_city)),
    'prize_min_ap', (select season_prize_min_ap from ambassador_settings),
    'prizes_enabled', (select season_prizes_enabled from ambassador_settings),
    'year', ambassador_current_year(),
    'computed_at', (select max(computed_at) from ambassador_rating_snapshot r, s where r.season_id = s.id),
    'leaders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'city', r.city, 'profile_id', p.id, 'name', p.display_name, 'username', p.username,
               'avatar_url', p.avatar_url, 'season_ap', r.season_ap, 'total_ap', r.total_ap,
               'prize_eligible', r.total_ap >= (select season_prize_min_ap from ambassador_settings))
             order by r.season_ap desc, r.total_ap desc, r.city)
      from ambassador_rating_snapshot r join s on r.season_id = s.id
      join profiles p on p.id = r.profile_id and p.status <> 'blocked'
      where r.place = 1 and not is_hidden_between(auth.uid(), p.id)), '[]'::jsonb)
  )
$$;

-- Рейтинг города за идущий сезон (топ-50 из снимка).
create function ambassador_rating(in_city text)
returns table (place integer, profile_id uuid, display_name text, username text, avatar_url text,
               season_ap bigint, total_ap integer)
language sql stable security definer set search_path = public as $$
  select r.place, p.id, p.display_name, p.username, p.avatar_url, r.season_ap, r.total_ap
  from ambassador_rating_snapshot r
  join profiles p on p.id = r.profile_id and p.status <> 'blocked'
  where r.season_id = ambassador_current_season() and r.city = in_city
    and not is_hidden_between(auth.uid(), p.id)
  order by r.place
$$;

-- Годовой конкурс (топ-50 из снимка).
create function ambassador_year_top()
returns table (place integer, profile_id uuid, display_name text, username text, avatar_url text,
               year_ap bigint, total_ap integer)
language sql stable security definer set search_path = public as $$
  select r.place, p.id, p.display_name, p.username, p.avatar_url, r.year_ap, r.total_ap
  from ambassador_year_snapshot r
  join profiles p on p.id = r.profile_id and p.status <> 'blocked'
  where r.year = ambassador_current_year() and not is_hidden_between(auth.uid(), p.id)
  order by r.place
$$;

-- Значок в профиле: действующий амбассадор или врио и его город.
create function ambassador_of(in_profile uuid)
returns table (city text, role text, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.city, a.role, a.ends_at from ambassadors a
  where a.profile_id = in_profile and a.ended_at is null
$$;

revoke all on function ambassador_current_year() from public, anon, authenticated;
revoke all on function ambassador_snapshot_refresh() from public, anon, authenticated;
revoke all on function ambassador_overview() from public, anon, authenticated;
revoke all on function ambassador_rating(text) from public, anon, authenticated;
revoke all on function ambassador_year_top() from public, anon, authenticated;
revoke all on function ambassador_of(uuid) from public, anon, authenticated;

grant execute on function ambassador_overview() to authenticated;
grant execute on function ambassador_rating(text) to authenticated;
grant execute on function ambassador_year_top() to authenticated;
grant execute on function ambassador_of(uuid) to authenticated;
-- Зал славы — из 0100: читает только таблицы амбассадоров и призов.
grant execute on function ambassador_hall() to authenticated;

select ambassador_snapshot_refresh();

select cron.schedule('ambassador-snapshot', '*/10 * * * *', 'select public.ambassador_snapshot_refresh()')
where not exists (select 1 from cron.job where jobname = 'ambassador-snapshot');
