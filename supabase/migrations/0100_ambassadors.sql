-- Амбассадоры городов (шаг 2 программы, docs/ambassadors-program.md).
--
-- Решения Алексея 16–17.10.2026:
--   * сезоны — кварталы 15.12–15.03, 15.03–15.06, 15.06–15.09, 15.09–15.12;
--     первый короткий: с запуска AP за активность (16.10) до 15.12.2026;
--   * рейтинг сезона — AP из score_events за сезон в городе (город пишется в
--     каждое начисление, 0099); при равенстве выше тот, у кого больше общий
--     баланс (profiles.social_score);
--   * участвуют только города из списка приложения; виртуальные авторы и
--     команда не участвуют;
--   * порога для статуса нет: первых амбассадоров назначают основатели, база
--     только считает рейтинг и черновик призов;
--   * сезонный приз — разовая акция: лидерам трёх разных городов по мировому
--     рейтингу при общем балансе от 20 000 AP; годовой — мировому лидеру по
--     AP за год (15.12 → 15.12), город не важен.
--
-- Всё здесь — только для service_role: решения основателя проводит скрипт.
-- Клиенту рейтинги и Зал славы откроются на шаге 3 вместе с экранами и
-- снимком рейтинга (сейчас каждый вызов считает журнал заново, и открытый
-- вызов дал бы любому способ нагружать базу).

-- ── города ──────────────────────────────────────────────────────────────────

create table ambassador_cities (
  name text primary key
);

-- Тот же список, что Cities.all в приложении (lib/features/discover/domain/entities/city.dart).
insert into ambassador_cities (name) values
  ('Сочи'), ('Москва'), ('Санкт-Петербург'), ('Краснодар'), ('Новосибирск'),
  ('Екатеринбург'), ('Казань'), ('Нижний Новгород'), ('Ростов-на-Дону'),
  ('Самара'), ('Уфа'), ('Красноярск'), ('Воронеж'), ('Калининград'), ('Владивосток');

-- Город в журнале AP (замена функции из 0099):
--   * написание приводится к списку («сочи » → «Сочи»), чтобы рейтинг сравнивал
--     город напрямую и шёл по индексу;
--   * списание без города (откат реферала, 0059) получает город последнего
--     начисления человека, а не текущий город профиля: иначе, сменив город,
--     можно было увести списание из рейтинга, где лежат баллы.
create or replace function score_event_city() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.city is null and new.delta < 0 then
    select e.city into new.city from score_events e
    where e.profile_id = new.profile_id and e.delta > 0 and e.city is not null
    order by e.created_at desc limit 1;
  end if;
  if new.city is null then
    select city into new.city from profiles where id = new.profile_id;
  end if;
  select coalesce((select c.name from ambassador_cities c where lower(c.name) = lower(trim(new.city))),
                  new.city)
    into new.city;
  return new;
end $$;

revoke all on function score_event_city() from public, anon, authenticated;

-- Начисления до 0099 шли без города, а у остальных написание могло отличаться.
-- Триггер баланса (0001) — только на вставку, обновление его не трогает.
update score_events e set city = p.city
from profiles p
where p.id = e.profile_id and e.city is null;

update score_events e set city = c.name
from ambassador_cities c
where lower(trim(e.city)) = lower(c.name) and e.city <> c.name;

-- ── сезоны и настройки ──────────────────────────────────────────────────────

create table ambassador_seasons (
  id           integer primary key,
  starts_at    timestamptz not null unique,
  ends_at      timestamptz not null check (ends_at > starts_at),
  status       text not null default 'open' check (status in ('open', 'counting', 'confirmed')),
  confirmed_at timestamptz
);

insert into ambassador_seasons (id, starts_at, ends_at) values
  (1, '2026-10-16 00:00+03', '2026-12-15 00:00+03'),
  (2, '2026-12-15 00:00+03', '2027-03-15 00:00+03'),
  (3, '2027-03-15 00:00+03', '2027-06-15 00:00+03'),
  (4, '2027-06-15 00:00+03', '2027-09-15 00:00+03'),
  (5, '2027-09-15 00:00+03', '2027-12-15 00:00+03'),
  (6, '2027-12-15 00:00+03', '2028-03-15 00:00+03'),
  (7, '2028-03-15 00:00+03', '2028-06-15 00:00+03'),
  (8, '2028-06-15 00:00+03', '2028-09-15 00:00+03'),
  (9, '2028-09-15 00:00+03', '2028-12-15 00:00+03');

create table ambassador_settings (
  id                    boolean primary key default true check (id),
  season_prize_min_ap   integer not null default 20000,
  season_prize_amount   integer not null default 30000,
  season_prize_count    integer not null default 3,
  -- Разовая акция: после первых утверждённых сезонных призов выключается сама.
  season_prizes_enabled boolean not null default true,
  year_prize_amount     integer not null default 100000
);

insert into ambassador_settings default values;

-- ── амбассадоры, призы, дисквалификации ─────────────────────────────────────

-- История живёт и после удаления аккаунта (ТЗ: имя остаётся навсегда, выплаты
-- нужны для отчёта), поэтому ссылка на профиль обнуляется, а имя хранится копией.
create table ambassadors (
  id                 bigint generated always as identity primary key,
  profile_id         uuid references profiles on delete set null,
  name               text not null,
  city               text not null references ambassador_cities,
  -- Конкурс, по которому назначен (для первых назначений — текущий сезон).
  season_id          integer not null references ambassador_seasons,
  role               text not null default 'ambassador' check (role in ('ambassador', 'acting')),
  starts_at          timestamptz not null default now(),
  ends_at            timestamptz not null,
  ended_at           timestamptz,
  end_reason         text check (end_reason in ('term', 'removed', 'resigned')),
  -- Выданный Premium и тот, что был до назначения: снятие возвращает прежний.
  premium_until      timestamptz,
  prev_premium_until timestamptz,
  note               text,
  created_at         timestamptz not null default now(),
  check (ends_at > starts_at)
);

-- Один действующий на город и один город на человека.
create unique index ambassadors_one_per_city on ambassadors (city) where ended_at is null;
create unique index ambassadors_one_per_person on ambassadors (profile_id) where ended_at is null;

create table ambassador_prizes (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('season', 'year')),
  season_id  integer references ambassador_seasons,
  year       integer,
  profile_id uuid references profiles on delete set null,
  name       text not null,
  city       text,
  amount     integer not null check (amount > 0),
  status     text not null default 'proposed' check (status in ('proposed', 'confirmed', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  check ((kind = 'season') = (season_id is not null)),
  check ((kind = 'year') = (year is not null))
);

create unique index ambassador_prizes_once on ambassador_prizes
  (kind, coalesce(season_id, 0), coalesce(year, 0), profile_id) where status <> 'cancelled';

-- Дисквалификация держится и за номер телефона: удалить аккаунт и
-- зарегистрироваться заново с тем же номером не помогает.
create table ambassador_bans (
  id         bigint generated always as identity primary key,
  profile_id uuid references profiles on delete set null,
  phone_hash text,
  scope      text not null check (scope in ('next_contest', 'lifetime')),
  -- Для next_contest — какой конкурс человек пропускает.
  season_id  integer references ambassador_seasons,
  reason     text not null check (char_length(reason) between 3 and 2000),
  created_at timestamptz not null default now(),
  lifted_at  timestamptz,
  check ((scope = 'next_contest') = (season_id is not null))
);

alter table ambassador_cities enable row level security;
alter table ambassador_seasons enable row level security;
alter table ambassador_settings enable row level security;
alter table ambassadors enable row level security;
alter table ambassador_prizes enable row level security;
alter table ambassador_bans enable row level security;
revoke all on ambassador_cities, ambassador_seasons, ambassador_settings,
  ambassadors, ambassador_prizes, ambassador_bans from public, anon, authenticated;

-- ── рейтинги ────────────────────────────────────────────────────────────────

-- Кто не участвует: виртуальные авторы, команда, дисквалифицированные (по
-- профилю или по номеру телефона). Без сезона — только пожизненные.
create function ambassador_excluded(in_profile uuid, in_season integer) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from bot_authors where profile_id = in_profile)
      or exists (select 1 from team_members where profile_id = in_profile)
      or exists (
        select 1 from ambassador_bans b
        where b.lifted_at is null
          and (b.scope = 'lifetime' or b.season_id = in_season)
          and (b.profile_id = in_profile
               or b.phone_hash in (select phone_hash from profile_phones
                                   where profile_id = in_profile and verified)))
$$;

-- Рейтинг города за сезон: сначала сумма по журналу (город и время — по
-- индексу), исключения — уже к готовым суммам.
create function ambassador_city_rating(in_season integer, in_city text, in_limit integer default 50)
returns table (place bigint, profile_id uuid, username text, display_name text, avatar_url text,
               season_ap bigint, total_ap integer)
language sql stable security definer set search_path = public as $$
  with s as (
    select starts_at, ends_at from ambassador_seasons where id = in_season
  ), agg as (
    select e.profile_id, sum(e.delta) as ap
    from s join score_events e
      on e.city = in_city and e.created_at >= s.starts_at and e.created_at < s.ends_at
    group by e.profile_id
    having sum(e.delta) > 0
  )
  select row_number() over (order by agg.ap desc, p.social_score desc, p.id),
         p.id, p.username, p.display_name, p.avatar_url, agg.ap, p.social_score
  from agg join profiles p on p.id = agg.profile_id and p.status <> 'blocked'
  where not ambassador_excluded(agg.profile_id, in_season)
  order by 1
  limit least(greatest(in_limit, 1), 200)
$$;

-- Мировой рейтинг лидеров городов за сезон и кто из них проходит на приз.
create function ambassador_world_leaders(in_season integer)
returns table (city text, profile_id uuid, username text, display_name text,
               season_ap bigint, total_ap integer, prize_eligible boolean)
language sql stable security definer set search_path = public as $$
  select c.name, l.profile_id, l.username, l.display_name, l.season_ap, l.total_ap,
         l.total_ap >= (select season_prize_min_ap from ambassador_settings)
  from ambassador_cities c
  cross join lateral ambassador_city_rating(in_season, c.name, 1) l
  order by l.season_ap desc, l.total_ap desc, c.name
$$;

-- Годовой конкурс: 15.12 прошлого года → 15.12 года in_year, все AP человека
-- вместе, без деления по городам (иначе списание в одном городе терялось бы).
create function ambassador_year_rating(in_year integer, in_limit integer default 50)
returns table (place bigint, profile_id uuid, username text, display_name text, avatar_url text,
               year_ap bigint, total_ap integer)
language sql stable security definer set search_path = public as $$
  with agg as (
    select e.profile_id, sum(e.delta) as ap
    from score_events e
    where e.created_at >= make_timestamptz(in_year - 1, 12, 15, 0, 0, 0, 'Europe/Moscow')
      and e.created_at < make_timestamptz(in_year, 12, 15, 0, 0, 0, 'Europe/Moscow')
    group by e.profile_id
    having sum(e.delta) > 0
  )
  select row_number() over (order by agg.ap desc, p.social_score desc, p.id),
         p.id, p.username, p.display_name, p.avatar_url, agg.ap, p.social_score
  from agg join profiles p on p.id = agg.profile_id and p.status <> 'blocked'
  where not ambassador_excluded(agg.profile_id, null)
  order by 1
  limit least(greatest(in_limit, 1), 200)
$$;

-- ── Зал славы ───────────────────────────────────────────────────────────────

-- Действующие и бывшие амбассадоры, врио (role = acting), призёры сезона и
-- победители года. Причину снятия не показываем: история говорит, кто занимал
-- должность. Удалённый аккаунт остаётся под сохранённым именем.
create function ambassador_hall()
returns table (kind text, profile_id uuid, name text, username text, avatar_url text,
               city text, role text, season_id integer, starts_at timestamptz, ends_at timestamptz,
               active boolean, year integer)
language sql stable security definer set search_path = public as $$
  select 'ambassador', a.profile_id, coalesce(p.display_name, a.name), p.username, p.avatar_url,
         a.city, a.role, a.season_id, a.starts_at, coalesce(a.ended_at, a.ends_at),
         a.ended_at is null, null::integer
  from ambassadors a left join profiles p on p.id = a.profile_id
  where p.id is null or p.status <> 'blocked'
  union all
  select z.kind || '_winner', z.profile_id, coalesce(p.display_name, z.name), p.username, p.avatar_url,
         z.city, null, z.season_id, null, null, false, z.year
  from ambassador_prizes z left join profiles p on p.id = z.profile_id
  where z.status in ('confirmed', 'paid') and (p.id is null or p.status <> 'blocked')
  order by 11 desc, 9 desc nulls last, 12 desc nulls last, 8 desc nulls last
$$;

-- ── решения основателя ──────────────────────────────────────────────────────

-- Текущий конкурс — сезон, который идёт сейчас.
create function ambassador_current_season() returns integer
language sql stable security definer set search_path = public as $$
  select id from ambassador_seasons where starts_at <= now() and ends_at > now()
$$;

-- Назначить амбассадора или врио по конкурсу in_season. Срок по умолчанию —
-- до конца следующего за ним сезона (выборы по итогам сезона, полномочия на
-- следующий); для первых назначений в идущем сезоне — до его конца.
create function ambassador_appoint(
  in_profile uuid, in_city text, in_season integer,
  in_role text default 'ambassador', in_ends_at timestamptz default null, in_note text default null
) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  s ambassador_seasons;
  p profiles;
  term_end timestamptz;
  new_id bigint;
begin
  select * into s from ambassador_seasons where id = in_season;
  if not found then
    raise exception 'season_not_found';
  end if;
  select * into p from profiles where id = in_profile and status <> 'blocked';
  if not found then
    raise exception 'profile_not_found';
  end if;
  if ambassador_excluded(in_profile, in_season) then
    raise exception 'profile_excluded';
  end if;
  term_end := coalesce(
    in_ends_at,
    case when s.ends_at > now() then s.ends_at
         else (select n.ends_at from ambassador_seasons n where n.starts_at >= s.ends_at
               order by n.starts_at limit 1)
    end);
  if term_end is null or term_end <= now() then
    raise exception 'term_already_over';
  end if;

  insert into ambassadors (profile_id, name, city, season_id, role, ends_at, premium_until,
                           prev_premium_until, note)
  values (in_profile, coalesce(p.display_name, p.username, 'Без имени'), in_city, in_season, in_role,
          term_end, greatest(coalesce(p.premium_until, now()), term_end), p.premium_until, in_note)
  returning id into new_id;

  update profiles set premium_until = greatest(coalesce(premium_until, now()), term_end)
  where id = in_profile;
  return new_id;
end $$;

-- Снять амбассадора: срок закрывается, Premium возвращается к тому, что было
-- до назначения, дисквалификация — на идущий конкурс (из его рейтинга и призов
-- человек выпадает сразу) или пожизненно. Возвращает кандидата в врио —
-- следующего подходящего из рейтинга конкурса, по которому был назначен.
create function ambassador_remove(in_ambassador bigint, in_reason text, in_scope text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a ambassadors;
  cur integer := ambassador_current_season();
  candidate uuid;
begin
  select * into a from ambassadors where id = in_ambassador and ended_at is null for update;
  if not found then
    raise exception 'ambassador_not_active';
  end if;
  if in_scope not in ('next_contest', 'lifetime') then
    raise exception 'bad_scope';
  end if;
  if in_scope = 'next_contest' and cur is null then
    raise exception 'no_current_season';
  end if;

  update ambassadors set ended_at = now(), end_reason = 'removed' where id = a.id;
  update profiles set premium_until = greatest(coalesce(a.prev_premium_until, now()), now())
  where id = a.profile_id and premium_until = a.premium_until;

  insert into ambassador_bans (profile_id, phone_hash, scope, season_id, reason)
  values (a.profile_id,
          (select phone_hash from profile_phones where profile_id = a.profile_id and verified),
          in_scope, case when in_scope = 'next_contest' then cur end, in_reason);

  update ambassador_prizes set status = 'cancelled', decided_at = now()
  where profile_id = a.profile_id and status = 'proposed';

  select r.profile_id into candidate
  from ambassador_city_rating(a.season_id, a.city, 50) r
  where r.profile_id is distinct from a.profile_id
    and not exists (select 1 from ambassadors x where x.profile_id = r.profile_id and x.ended_at is null)
  order by r.place
  limit 1;
  return candidate;
end $$;

-- Итоги сезона: статус «подсчёт» и черновик сезонных призов (пока акция не
-- разыграна) — лидеры трёх разных городов по мировому рейтингу, у кого общий
-- баланс от порога. Ждём, пока подтвердятся последние начисления сезона.
create function ambassador_season_close(in_season integer) returns integer
language plpgsql security definer set search_path = public as $$
declare
  st ambassador_settings;
  n integer := 0;
begin
  select * into st from ambassador_settings;
  update ambassador_seasons set status = 'counting'
  where id = in_season and status = 'open'
    and ends_at + make_interval(hours => (select coalesce(max(hold_hours), 0) from activity_rules)) <= now();
  if not found then
    raise exception 'season_not_finished_or_not_open';
  end if;

  if st.season_prizes_enabled then
    insert into ambassador_prizes (kind, season_id, profile_id, name, city, amount)
    select 'season', in_season, l.profile_id, coalesce(l.display_name, l.username, 'Без имени'),
           l.city, st.season_prize_amount
    from ambassador_world_leaders(in_season) l
    where l.prize_eligible
    order by l.season_ap desc, l.total_ap desc, l.city
    limit st.season_prize_count;
    get diagnostics n = row_count;
  end if;
  return n;
end $$;

-- Основатель проверил итоги: призы сезона утверждены, сезон закрыт. Если
-- сезонные призы утверждены — акция разыграна и больше не повторяется.
create function ambassador_season_confirm(in_season integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  update ambassador_seasons set status = 'confirmed', confirmed_at = now()
  where id = in_season and status = 'counting';
  if not found then
    raise exception 'season_not_counting';
  end if;
  update ambassador_prizes set status = 'confirmed', decided_at = now()
  where season_id = in_season and status = 'proposed';
  if found then
    update ambassador_settings set season_prizes_enabled = false;
  end if;
end $$;

-- Черновик годового приза: мировой лидер по AP за год.
create function ambassador_year_close(in_year integer) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  w record;
begin
  if now() < make_timestamptz(in_year, 12, 15, 0, 0, 0, 'Europe/Moscow')
             + make_interval(hours => (select coalesce(max(hold_hours), 0) from activity_rules)) then
    raise exception 'year_not_finished';
  end if;
  select * into w from ambassador_year_rating(in_year, 1);
  if w.profile_id is not null then
    insert into ambassador_prizes (kind, year, profile_id, name, amount)
    values ('year', in_year, w.profile_id, coalesce(w.display_name, w.username, 'Без имени'),
            (select year_prize_amount from ambassador_settings))
    on conflict do nothing;
  end if;
  return w.profile_id;
end $$;

-- Приз утвердить / отметить выплату / отменить.
create function ambassador_prize_set(in_prize bigint, in_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if in_status not in ('confirmed', 'paid', 'cancelled') then
    raise exception 'bad_status';
  end if;
  update ambassador_prizes set status = in_status, decided_at = now() where id = in_prize;
  if not found then
    raise exception 'prize_not_found';
  end if;
end $$;

-- Раз в сутки: у кого срок вышел — закрыть. Premium сам истечёт по premium_until.
create function ambassador_tick() returns integer
language sql security definer set search_path = public as $$
  with done as (
    update ambassadors set ended_at = ends_at, end_reason = 'term'
    where ended_at is null and ends_at <= now()
    returning 1
  )
  select count(*)::integer from done
$$;

revoke all on function ambassador_excluded(uuid, integer) from public, anon, authenticated;
revoke all on function ambassador_city_rating(integer, text, integer) from public, anon, authenticated;
revoke all on function ambassador_world_leaders(integer) from public, anon, authenticated;
revoke all on function ambassador_year_rating(integer, integer) from public, anon, authenticated;
revoke all on function ambassador_hall() from public, anon, authenticated;
revoke all on function ambassador_current_season() from public, anon, authenticated;
revoke all on function ambassador_appoint(uuid, text, integer, text, timestamptz, text) from public, anon, authenticated;
revoke all on function ambassador_remove(bigint, text, text) from public, anon, authenticated;
revoke all on function ambassador_season_close(integer) from public, anon, authenticated;
revoke all on function ambassador_season_confirm(integer) from public, anon, authenticated;
revoke all on function ambassador_year_close(integer) from public, anon, authenticated;
revoke all on function ambassador_prize_set(bigint, text) from public, anon, authenticated;
revoke all on function ambassador_tick() from public, anon, authenticated;

select cron.schedule('ambassador-tick', '17 3 * * *', 'select public.ambassador_tick()')
where not exists (select 1 from cron.job where jobname = 'ambassador-tick');
