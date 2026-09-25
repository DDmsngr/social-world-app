-- Квесты, «Мне надо», квест-чаты, Quest Moment (ТЗ ChaWo 1/3, п. 15, 20–51).
--
-- Зависит от 0015 (is_hidden_between, can_see_post, enforce_rate_limit) и 0016
-- (notifications, add_notification, activity_config, city_activity).
--
-- Принципы:
--   1. Квесты — отдельная сущность. События (events) не трогаем.
--   2. Таблицы квестов и просьб закрыты для прямых запросов целиком: читать и
--      писать можно только через функции ниже. Так у QR-кода квеста нет шанса
--      утечь через `select *`, а правила ТЗ (лимит мест, кто кого одобряет,
--      приватность участий) проверяет база, а не экран.
--   3. Чужие участия не видны никому, кроме организатора и соучастников
--      (ТЗ, п. 43, 44, 52): «где сейчас человек» из базы не достать.
--   4. Имена политик и функций — латиницей (см. заметку в 0015).

-- ── общий генератор кода прибытия ───────────────────────────────────────────
-- 8 символов без похожих друг на друга (0/O, 1/I/L). Случайность — из
-- gen_random_uuid (ядро Postgres), а не pgcrypto: у Supabase pgcrypto живёт в
-- схеме extensions, и функции с search_path = public его бы не нашли.
-- Байты 6 и 8 у UUID v4 служебные (версия и вариант) — их пропускаем.

create function quest_new_code() returns text
language sql volatile set search_path = public as $$
  select string_agg(
           substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + get_byte(r.b, i) % 31, 1),
           '' order by i)
  from (select uuid_send(gen_random_uuid()) as b) r
  cross join unnest(array[0, 1, 2, 3, 4, 5, 9, 10]) as i;
$$;

revoke all on function quest_new_code from public;

-- ── квесты ──────────────────────────────────────────────────────────────────

create table quests (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null references profiles on delete cascade,
  title            text not null check (char_length(title) between 3 and 120),
  description      text check (description is null or char_length(description) <= 2000),
  extra_info       text check (extra_info is null or char_length(extra_info) <= 1000),
  photo_url        text,
  -- Место встречи: либо заведение из places, либо точка, поставленная
  -- организатором (адрес/название — в place_title). Это публичная точка
  -- встречи, а не координата человека.
  place_id         uuid references places on delete set null,
  place_title      text check (place_title is null or char_length(place_title) <= 200),
  geo              geography(point, 4326),
  starts_at        timestamptz not null,
  -- Долгоживущий квест: организатор может держать его открытым днями (п. 35).
  ends_at          timestamptz check (ends_at is null or ends_at > starts_at),
  -- null — без лимита; тогда заявки одобряются сами (п. 26 говорит об
  -- управлении заявками только для ограниченных квестов).
  max_participants integer check (max_participants is null or max_participants between 1 and 1000),
  status           text not null default 'active'
                     check (status in ('active', 'finished', 'cancelled')),
  finished_at      timestamptz,
  moderation       moderation_status not null default 'active',
  arrival_code     text not null default quest_new_code(),
  created_at       timestamptz not null default now()
);

create index quests_geo_idx on quests using gist (geo);
create index quests_author_idx on quests (author_id, created_at desc);
create index quests_status_idx on quests (status, starts_at);

alter table quests enable row level security;
revoke all on quests from anon, authenticated;

create trigger quests_rate_limit before insert on quests
  for each row execute function enforce_rate_limit('author_id', '3600', '10');

-- Участие — отдельная строка на пару (квест, человек): у одного человека
-- может быть сколько угодно активных участий одновременно (п. 25), поля
-- «текущий квест» нет. Повторное участие в долгом квесте переиспользует
-- строку (п. 35, 36): состав меняется, история дней — в отметках времени.
create table quest_participations (
  id           uuid primary key default gen_random_uuid(),
  quest_id     uuid not null references quests on delete cascade,
  profile_id   uuid not null references profiles on delete cascade,
  status       text not null default 'requested' check (status in (
                 'requested', 'approved', 'rejected', 'arrived',
                 'completed', 'withdrawn', 'removed')),
  requested_at timestamptz not null default now(),
  decided_at   timestamptz,
  arrived_at   timestamptz,
  completed_at timestamptz,
  unique (quest_id, profile_id)
);

create index quest_participations_profile_idx
  on quest_participations (profile_id, requested_at desc);
create index quest_participations_quest_idx
  on quest_participations (quest_id, status);

alter table quest_participations enable row level security;
revoke all on quest_participations from anon, authenticated;

-- Согласие с правилами квестов: кто, какая версия, когда (п. 49, 50).
create table quest_rules_consents (
  profile_id  uuid not null references profiles on delete cascade,
  version     integer not null check (version > 0),
  accepted_at timestamptz not null default now(),
  primary key (profile_id, version)
);

alter table quest_rules_consents enable row level security;
revoke all on quest_rules_consents from anon, authenticated;

-- Действующая версия правил. Поднять при существенном изменении текста —
-- и всем придётся принять их заново перед созданием квеста.
create function quest_rules_version() returns integer
language sql immutable as $$ select 1 $$;

grant execute on function quest_rules_version to authenticated;
-- Связь момента с квестом (Quest Moment, п. 37–39). Колонка нужна уже функциям
-- чтения ниже: SQL-функции проверяют колонки при создании, а не при вызове.
-- Один момент на человека на квест — уникальный индекс; остальные проверки
-- (участник, одно фото) — триггер в конце файла.
alter table posts add column quest_id uuid references quests on delete set null;

create unique index posts_one_moment_per_quest
  on posts (author_id, quest_id) where quest_id is not null;

-- ── служебное ───────────────────────────────────────────────────────────────

-- Сколько мест занято: одобренные и пришедшие.
create function quest_taken_slots(in_quest uuid) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from quest_participations
  where quest_id = in_quest and status in ('approved', 'arrived');
$$;

revoke all on function quest_taken_slots from public;

create function quest_is_open(q quests) returns boolean
language sql stable as $$
  select q.status = 'active'
     and q.moderation = 'active'
     and (q.ends_at is null or q.ends_at > now());
$$;

revoke all on function quest_is_open from public;

-- ── чтение ──────────────────────────────────────────────────────────────────
-- Одна функция на все выборки: Pulse, карточка по id, «мои», «созданные
-- мной». Одинаковая форма строк — один парсер на клиенте.
--
-- in_scope:
--   nearby   — Pulse: идущие квесты в радиусе + след завершённых квестов с
--              Moments ещё сутки после завершения (п. 42);
--   one      — один квест по id (ссылка, уведомление, QR);
--   mine     — мои участия (только свои — п. 43, 44);
--   authored — созданные мной.

create function quests_list(
  in_scope       text,
  in_lat         double precision default null,
  in_lng         double precision default null,
  in_radius_m    integer default 5000,
  in_at          timestamptz default now(),
  in_quest       uuid default null,
  in_active_only boolean default false,
  in_limit       integer default 100
)
returns table (
  id                uuid,
  author_id         uuid,
  author_name       text,
  avatar_url        text,
  title             text,
  description       text,
  extra_info        text,
  photo_url         text,
  place_id          uuid,
  place_title       text,
  latitude          double precision,
  longitude         double precision,
  starts_at         timestamptz,
  ends_at           timestamptz,
  max_participants  integer,
  participant_count integer,
  status            text,
  finished_at       timestamptz,
  my_status         text,
  moment_count      integer,
  is_trail          boolean,
  created_at        timestamptz
)
language sql stable security definer set search_path = public as $$
  with base as (
    select q.*,
           coalesce(q.geo, pl.geo) as point,
           coalesce(q.place_title, pl.title) as where_title,
           mp.status as mine,
           (select count(*)::integer from posts p
             where p.quest_id = q.id and p.status = 'active'
               and p.visibility = 'public') as moments,
           -- Когда квест перестал идти: завершён организатором или истёк.
           coalesce(q.finished_at,
                    case when q.ends_at is not null and q.ends_at <= in_at
                         then q.ends_at end) as over_at
    from quests q
    left join places pl on pl.id = q.place_id
    left join quest_participations mp
           on mp.quest_id = q.id and mp.profile_id = auth.uid()
    join profiles pr on pr.id = q.author_id
    where pr.status <> 'blocked'
      and q.moderation = 'active'
      and not is_hidden_between(auth.uid(), q.author_id)
      and not exists (
        select 1 from reports r
        where r.reporter_id = auth.uid()
          and r.status in ('new', 'in_review')
          and r.target::text = 'quest' and r.target_id = q.id
      )
      and case in_scope
        when 'one'      then q.id = in_quest
        when 'mine'     then mp.profile_id is not null
                         and mp.status not in ('rejected', 'removed')
        when 'authored' then q.author_id = auth.uid()
        when 'nearby'   then q.status <> 'cancelled'
                         and in_lat is not null and in_lng is not null
                         and st_dwithin(
                               coalesce(q.geo, pl.geo),
                               st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography,
                               least(greatest(in_radius_m, 300), 20000))
        else false
      end
  )
  select b.id,
         b.author_id,
         pr.display_name,
         pr.avatar_url,
         b.title,
         b.description,
         b.extra_info,
         b.photo_url,
         b.place_id,
         b.where_title,
         st_y(b.point::geometry),
         st_x(b.point::geometry),
         b.starts_at,
         b.ends_at,
         b.max_participants,
         quest_taken_slots(b.id),
         case when b.status = 'active' and b.over_at is not null
              then 'finished' else b.status end,
         b.over_at,
         b.mine,
         b.moments,
         b.over_at is not null,
         b.created_at
  from base b
  join profiles pr on pr.id = b.author_id
  where case in_scope
    -- На Pulse: идёт или завершился меньше суток назад и оставил Moments.
    when 'nearby' then b.over_at is null
                    or (b.moments > 0 and b.over_at > in_at - interval '24 hours')
    when 'mine' then not in_active_only
                  or (b.mine in ('requested', 'approved', 'arrived')
                      and b.status = 'active' and b.over_at is null)
    when 'authored' then not in_active_only
                      or (b.status = 'active' and b.over_at is null)
    else true
  end
  order by case when in_scope in ('mine', 'authored') then b.created_at end desc,
           b.starts_at asc
  limit least(in_limit, 200);
$$;

revoke all on function quests_list from public;
grant execute on function quests_list to authenticated;

-- Кто участвует. Организатор видит всех, включая заявки и очки активности
-- заявителей (п. 26); одобренные участники — друг друга (они и так вместе в
-- квест-чате); остальные — никого, только счётчик на карточке (п. 44, 52).
create function quest_participants(in_quest uuid)
returns table (
  id           uuid,
  profile_id   uuid,
  display_name text,
  avatar_url   text,
  social_score integer,
  status       text,
  requested_at timestamptz,
  arrived_at   timestamptz,
  completed_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select qp.id, qp.profile_id, p.display_name, p.avatar_url, p.social_score,
         qp.status, qp.requested_at, qp.arrived_at, qp.completed_at
  from quest_participations qp
  join quests q on q.id = qp.quest_id
  join profiles p on p.id = qp.profile_id
  where qp.quest_id = in_quest
    and p.status <> 'blocked'
    and not is_hidden_between(auth.uid(), qp.profile_id)
    and (
      q.author_id = auth.uid()
      or (
        qp.status in ('approved', 'arrived')
        and exists (
          select 1 from quest_participations me
          where me.quest_id = in_quest
            and me.profile_id = auth.uid()
            and me.status in ('approved', 'arrived')
        )
      )
    )
  order by case qp.status when 'requested' then 0 else 1 end, qp.requested_at
  limit 500;
$$;

revoke all on function quest_participants from public;
grant execute on function quest_participants to authenticated;

-- Социальная история квеста: только те, кто сам опубликовал Moment (п. 40),
-- по времени. Это не список участников.
create function quest_moments(in_quest uuid, in_limit integer default 100)
returns table (
  post_id     uuid,
  author_id   uuid,
  author_name text,
  avatar_url  text,
  photo_url   text,
  body        text,
  created_at  timestamptz
)
language sql stable security definer set search_path = public as $$
  select p.id, p.author_id, pr.display_name, pr.avatar_url,
         p.media_urls[1], p.body, p.created_at
  from posts p
  join profiles pr on pr.id = p.author_id
  where p.quest_id = in_quest
    and p.status = 'active'
    and pr.status <> 'blocked'
    and can_see_post(p.author_id, p.visibility)
    and not is_hidden_between(auth.uid(), p.author_id)
  order by p.created_at asc
  limit least(in_limit, 200);
$$;

revoke all on function quest_moments from public;
grant execute on function quest_moments to authenticated;

-- ── правила ─────────────────────────────────────────────────────────────────

create function my_quest_rules_consent()
returns table (version integer, accepted_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.version, c.accepted_at from quest_rules_consents c
  where c.profile_id = auth.uid()
  order by c.version desc
  limit 1;
$$;

create function accept_quest_rules(in_version integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  -- Принять можно только действующую версию: «согласие» на несуществующие
  -- правила ничего не значит.
  if in_version <> quest_rules_version() then
    raise exception 'quest_rules_outdated' using errcode = 'P0001';
  end if;
  insert into quest_rules_consents (profile_id, version)
  values (auth.uid(), in_version)
  on conflict do nothing;
end;
$$;

revoke all on function my_quest_rules_consent, accept_quest_rules from public;
grant execute on function my_quest_rules_consent, accept_quest_rules to authenticated;

-- ── действия организатора ───────────────────────────────────────────────────

create function create_quest(
  in_title            text,
  in_starts_at        timestamptz,
  in_description      text default null,
  in_extra_info       text default null,
  in_photo_url        text default null,
  in_place_id         uuid default null,
  in_place_title      text default null,
  in_lat              double precision default null,
  in_lng              double precision default null,
  in_ends_at          timestamptz default null,
  in_max_participants integer default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from profiles where id = me and status = 'active') then
    raise exception 'profile_limited' using errcode = 'P0001';
  end if;
  -- Перед первым квестом — правила (п. 49). Сервер проверяет сам: форму в
  -- приложении можно и обойти.
  if not exists (
    select 1 from quest_rules_consents
    where profile_id = me and version >= quest_rules_version()
  ) then
    raise exception 'quest_rules_required' using errcode = 'P0001';
  end if;
  if in_starts_at < now() - interval '1 hour' then
    raise exception 'quest_starts_in_past' using errcode = 'P0001';
  end if;
  if (in_lat is null) <> (in_lng is null)
     or in_lat not between -90 and 90 or in_lng not between -180 and 180 then
    raise exception 'quest_bad_point' using errcode = 'P0001';
  end if;

  insert into quests (
    author_id, title, description, extra_info, photo_url,
    place_id, place_title, geo, starts_at, ends_at, max_participants
  ) values (
    me,
    trim(in_title),
    nullif(trim(in_description), ''),
    nullif(trim(in_extra_info), ''),
    nullif(trim(in_photo_url), ''),
    in_place_id,
    nullif(trim(in_place_title), ''),
    case when in_lat is not null
         then st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography end,
    in_starts_at,
    in_ends_at,
    in_max_participants
  )
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function create_quest from public;
grant execute on function create_quest to authenticated;

-- Проверка «это мой квест» с блокировкой строки: решения по заявкам идут
-- по очереди, и два одновременных «Принять» не займут одно место дважды.
create function quest_lock_own(in_quest uuid) returns quests
language plpgsql security definer set search_path = public as $$
declare q quests;
begin
  select * into q from quests where id = in_quest for update;
  if not found or q.author_id is distinct from auth.uid() then
    raise exception 'quest_not_yours' using errcode = 'P0001';
  end if;
  return q;
end;
$$;

revoke all on function quest_lock_own from public;

create function quest_decide(in_participation uuid, in_approve boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  part quest_participations;
  q quests;
  next_status text;
begin
  select * into part from quest_participations where id = in_participation;
  if not found then raise exception 'quest_request_not_found' using errcode = 'P0001'; end if;
  q := quest_lock_own(part.quest_id);

  if part.status <> 'requested' then return part.status; end if;

  if in_approve then
    if not quest_is_open(q) then
      raise exception 'quest_closed' using errcode = 'P0001';
    end if;
    if q.max_participants is not null
       and quest_taken_slots(q.id) >= q.max_participants then
      raise exception 'quest_full' using errcode = 'P0001';
    end if;
    next_status := 'approved';
  else
    next_status := 'rejected';
  end if;

  update quest_participations
     set status = next_status, decided_at = now()
   where id = in_participation;
  return next_status;
end;
$$;

-- Исключить участника (п. 31): он выходит из квест-чата вместе с этим.
create function quest_remove_participant(in_participation uuid) returns void
language plpgsql security definer set search_path = public as $$
declare part quest_participations;
begin
  select * into part from quest_participations where id = in_participation;
  if not found then raise exception 'quest_request_not_found' using errcode = 'P0001'; end if;
  perform quest_lock_own(part.quest_id);
  update quest_participations
     set status = 'removed', decided_at = now()
   where id = in_participation
     and status in ('requested', 'approved', 'arrived');
end;
$$;

create function quest_finish(in_quest uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform quest_lock_own(in_quest);
  update quests set status = 'finished', finished_at = now()
   where id = in_quest and status = 'active';
end;
$$;

create function quest_cancel(in_quest uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform quest_lock_own(in_quest);
  update quests set status = 'cancelled', finished_at = now()
   where id = in_quest and status = 'active';
end;
$$;

-- QR показывает организатор: код видит только он.
create function quest_arrival_code(in_quest uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare code text;
begin
  select arrival_code into code from quests
  where id = in_quest and author_id = auth.uid();
  if code is null then raise exception 'quest_not_yours' using errcode = 'P0001'; end if;
  return code;
end;
$$;

-- Код утёк (сфотографировали и разослали) — организатор меняет его.
create function quest_rotate_code(in_quest uuid) returns text
language plpgsql security definer set search_path = public as $$
declare code text := quest_new_code();
begin
  perform quest_lock_own(in_quest);
  update quests set arrival_code = code where id = in_quest;
  return code;
end;
$$;

revoke all on function quest_decide, quest_remove_participant, quest_finish,
  quest_cancel, quest_arrival_code, quest_rotate_code from public;
grant execute on function quest_decide, quest_remove_participant, quest_finish,
  quest_cancel, quest_arrival_code, quest_rotate_code to authenticated;

-- ── действия участника ───────────────────────────────────────────────────────

-- Заявка. Идемпотентна: повторный вызов возвращает текущий статус. Для
-- квеста без лимита заявка одобряется сразу.
create function quest_request_join(in_quest uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  q quests;
  part quest_participations;
  next_status text;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into q from quests where id = in_quest for update;
  if not found then raise exception 'quest_not_found' using errcode = 'P0001'; end if;
  if q.author_id = me then raise exception 'quest_is_yours' using errcode = 'P0001'; end if;
  if is_hidden_between(me, q.author_id) or is_hidden_between(q.author_id, me) then
    raise exception 'quest_not_found' using errcode = 'P0001';
  end if;

  select * into part from quest_participations
  where quest_id = in_quest and profile_id = me;

  if found then
    if part.status in ('requested', 'approved', 'arrived') then return part.status; end if;
    if part.status in ('rejected', 'removed') then
      raise exception 'quest_denied' using errcode = 'P0001';
    end if;
  end if;

  if not quest_is_open(q) then raise exception 'quest_closed' using errcode = 'P0001'; end if;
  if q.max_participants is not null
     and quest_taken_slots(q.id) >= q.max_participants then
    raise exception 'quest_full' using errcode = 'P0001';
  end if;

  next_status := case when q.max_participants is null then 'approved' else 'requested' end;

  insert into quest_participations (quest_id, profile_id, status, requested_at, decided_at)
  values (in_quest, me, next_status, now(),
          case when next_status = 'approved' then now() end)
  on conflict (quest_id, profile_id) do update
    set status = excluded.status,
        requested_at = excluded.requested_at,
        decided_at = excluded.decided_at,
        arrived_at = null,
        completed_at = null;

  return next_status;
end;
$$;

create function quest_withdraw(in_quest uuid) returns void
language sql security definer set search_path = public as $$
  update quest_participations
     set status = 'withdrawn'
   where quest_id = in_quest
     and profile_id = auth.uid()
     and status in ('requested', 'approved', 'arrived');
$$;

-- Своё участие завершается независимо от остальных (п. 34).
create function quest_complete(in_quest uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update quest_participations
     set status = 'completed', completed_at = now()
   where quest_id = in_quest
     and profile_id = auth.uid()
     and status in ('approved', 'arrived');
  -- Повтор (второе нажатие при плохой связи) — не ошибка.
  if not found and not exists (
    select 1 from quest_participations
    where quest_id = in_quest and profile_id = auth.uid() and status = 'completed'
  ) then
    raise exception 'quest_not_participating' using errcode = 'P0001';
  end if;
end;
$$;

-- Прибытие по QR (п. 32). После этого приложение за человеком не следит —
-- ни маршрута, ни таймера, ни GPS (п. 33): здесь нет ни одной координаты.
create function quest_confirm_arrival(in_quest uuid, in_code text) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  q quests;
  part quest_participations;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into q from quests where id = in_quest for update;
  if not found then raise exception 'quest_not_found' using errcode = 'P0001'; end if;
  if q.author_id = me then raise exception 'quest_is_yours' using errcode = 'P0001'; end if;
  if upper(regexp_replace(coalesce(in_code, ''), '[^A-Za-z0-9]', '', 'g')) <> q.arrival_code then
    raise exception 'quest_bad_code' using errcode = 'P0001';
  end if;
  if not quest_is_open(q) then raise exception 'quest_closed' using errcode = 'P0001'; end if;

  select * into part from quest_participations
  where quest_id = in_quest and profile_id = me;

  if found and part.status = 'arrived' then return 'arrived'; end if;
  if found and part.status in ('rejected', 'removed') then
    raise exception 'quest_denied' using errcode = 'P0001';
  end if;
  if found and part.status = 'approved' then
    update quest_participations set status = 'arrived', arrived_at = now()
     where id = part.id;
    return 'arrived';
  end if;

  -- Без одобрения на месте можно отметиться только в квесте без лимита:
  -- там заявка всё равно одобрилась бы сама («пришёл на прогулку — участвую»).
  if q.max_participants is not null then
    raise exception 'quest_not_approved' using errcode = 'P0001';
  end if;

  insert into quest_participations (quest_id, profile_id, status, requested_at, decided_at, arrived_at)
  values (in_quest, me, 'arrived', now(), now(), now())
  on conflict (quest_id, profile_id) do update
    set status = 'arrived', requested_at = now(), decided_at = now(),
        arrived_at = now(), completed_at = null;
  return 'arrived';
end;
$$;

revoke all on function quest_request_join, quest_withdraw, quest_complete,
  quest_confirm_arrival from public;
grant execute on function quest_request_join, quest_withdraw, quest_complete,
  quest_confirm_arrival to authenticated;

-- ── квест-чат (п. 29–31) ────────────────────────────────────────────────────
-- Чат создаётся вместе с квестом, состав следует за статусами участия сам:
-- организатор + одобренные и пришедшие. Завершил, отказался, исключён — вышел
-- из чата; сообщения остаются остальным. Квест закрыт — чат закрыт.
--
-- Переписка в продукте пока выключена (0014, вопрос ОРИ): писать в чат всё
-- равно нельзя, пока не вернут права на chat_messages. Состав при этом
-- ведётся уже сейчас, чтобы включение чатов не требовало миграции данных.

alter table chat_conversations
  add column quest_id  uuid unique references quests on delete cascade,
  add column closed_at timestamptz;

create function is_chat_open(in_conversation uuid) returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select not exists (
    select 1 from chat_conversations
    where id = in_conversation and closed_at is not null
  );
$$;

revoke all on function is_chat_open from public;
grant execute on function is_chat_open to authenticated;

-- restrictive: складывается с существующей политикой вставки через AND.
create policy chat_messages_open_only
  on chat_messages as restrictive for insert to authenticated
  with check (is_chat_open(conversation_id));

create function trg_quest_chat_create() returns trigger
language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  insert into chat_conversations (quest_id) values (new.id) returning id into conv;
  insert into chat_members (conversation_id, profile_id) values (conv, new.author_id);
  return new;
end;
$$;

create trigger quest_chat_on_create after insert on quests
  for each row execute function trg_quest_chat_create();

create function trg_quest_chat_membership() returns trigger
language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  select id into conv from chat_conversations where quest_id = new.quest_id;
  if conv is null then return new; end if;
  if new.status in ('approved', 'arrived') then
    insert into chat_members (conversation_id, profile_id)
    values (conv, new.profile_id)
    on conflict do nothing;
  else
    delete from chat_members
    where conversation_id = conv and profile_id = new.profile_id;
  end if;
  return new;
end;
$$;

create trigger quest_chat_membership after insert or update of status on quest_participations
  for each row execute function trg_quest_chat_membership();

create function trg_quest_chat_close() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status <> 'active' and old.status = 'active' then
    update chat_conversations set closed_at = now() where quest_id = new.id;
  end if;
  return new;
end;
$$;

create trigger quest_chat_on_close after update of status on quests
  for each row execute function trg_quest_chat_close();

-- ── Quest Moment (п. 37–40, 46) ─────────────────────────────────────────────
-- Обычный Moment с дополнительной связью. Один на человека на квест и не
-- больше одной фотографии (п. 38). Лимит 30 в сутки/час — общий, тот же
-- триггер posts_rate_limit.


create function trg_check_quest_moment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.quest_id is null then return new; end if;
  if new.post_type <> 'moment' then
    raise exception 'quest_moment_not_moment' using errcode = 'P0001';
  end if;
  if coalesce(cardinality(new.media_urls), 0) > 1 then
    raise exception 'quest_moment_one_photo' using errcode = 'P0001';
  end if;
  -- Связать Moment с квестом может только тот, кто в нём был: организатор
  -- или участник, которого одобрили.
  if not exists (
    select 1 from quests q
    where q.id = new.quest_id
      and (q.author_id = new.author_id or exists (
        select 1 from quest_participations qp
        where qp.quest_id = q.id and qp.profile_id = new.author_id
          and qp.status in ('approved', 'arrived', 'completed')
      ))
  ) then
    raise exception 'quest_moment_not_participant' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger posts_check_quest_moment before insert on posts
  for each row execute function trg_check_quest_moment();

-- Привязку к квесту после публикации не меняют: grant update из 0015 не
-- включает quest_id, и так и остаётся.

-- ── уведомления ─────────────────────────────────────────────────────────────

alter table notifications drop constraint notifications_kind_check;
alter table notifications add constraint notifications_kind_check check (kind in (
  'follow', 'comment', 'reply', 'reaction',
  'event_join', 'event_changed', 'event_cancelled', 'message',
  'quest_request', 'quest_join', 'quest_approved', 'quest_rejected',
  'quest_removed', 'quest_cancelled', 'need_response'
));

alter table notifications drop constraint notifications_target_type_check;
alter table notifications add constraint notifications_target_type_check
  check (target_type in ('profile', 'post', 'event', 'place', 'route', 'quest', 'need'));

create function trg_notify_quest_participation() returns trigger
language plpgsql security definer set search_path = public as $$
declare q quests;
begin
  if tg_op = 'UPDATE' and new.status = old.status then return new; end if;
  select * into q from quests where id = new.quest_id;

  if new.status = 'requested' then
    perform add_notification(q.author_id, new.profile_id, 'quest_request', 'quest', q.id, q.title);
  elsif new.status = 'approved' and auth.uid() = new.profile_id then
    -- Сам присоединился к квесту без лимита — организатору «новый участник».
    perform add_notification(q.author_id, new.profile_id, 'quest_join', 'quest', q.id, q.title);
  elsif new.status = 'approved' then
    perform add_notification(new.profile_id, q.author_id, 'quest_approved', 'quest', q.id, q.title);
  elsif new.status = 'rejected' then
    perform add_notification(new.profile_id, q.author_id, 'quest_rejected', 'quest', q.id, q.title);
  elsif new.status = 'removed' then
    perform add_notification(new.profile_id, q.author_id, 'quest_removed', 'quest', q.id, q.title);
  end if;
  return new;
end;
$$;

create trigger notify_on_quest_participation
  after insert or update of status on quest_participations
  for each row execute function trg_notify_quest_participation();

create function trg_notify_quest_cancelled() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    for r in
      select profile_id from quest_participations
      where quest_id = new.id and status in ('requested', 'approved', 'arrived')
    loop
      perform add_notification(r.profile_id, new.author_id, 'quest_cancelled', 'quest', new.id, new.title);
    end loop;
  end if;
  return new;
end;
$$;

create trigger notify_on_quest_cancelled after update of status on quests
  for each row execute function trg_notify_quest_cancelled();

-- ── «Мне надо» (п. 15) ──────────────────────────────────────────────────────

create table needs (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references profiles on delete cascade,
  body        text not null check (char_length(body) between 3 and 500),
  place_id    uuid references places on delete set null,
  place_title text check (place_title is null or char_length(place_title) <= 200),
  -- Точка, которую поставил автор. Наружу отдаётся размытой (см. city_needs):
  -- «установить телевизор» — это чаще всего чей-то дом.
  geo         geography(point, 4326),
  status      text not null default 'open' check (status in ('open', 'closed')),
  moderation  moderation_status not null default 'active',
  expires_at  timestamptz,
  closed_at   timestamptz,
  created_at  timestamptz not null default now()
);

create index needs_geo_idx on needs using gist (geo);
create index needs_author_idx on needs (author_id, created_at desc);

alter table needs enable row level security;
revoke all on needs from anon, authenticated;

create trigger needs_rate_limit before insert on needs
  for each row execute function enforce_rate_limit('author_id', '3600', '10');

-- Отклик «могу помочь». Публичный, как комментарий: личной переписки в
-- продукте пока нет (0014), и отклик её не подменяет.
create table need_responses (
  id         uuid primary key default gen_random_uuid(),
  need_id    uuid not null references needs on delete cascade,
  author_id  uuid not null references profiles on delete cascade,
  body       text check (body is null or char_length(body) <= 300),
  created_at timestamptz not null default now(),
  unique (need_id, author_id)
);

alter table need_responses enable row level security;
revoke all on need_responses from anon, authenticated;

create trigger need_responses_rate_limit before insert on need_responses
  for each row execute function enforce_rate_limit('author_id', '3600', '30');

-- Размытие точки просьбы до сетки ~300 м. Привязка к заведению — публичное
-- место, его координата отдаётся как есть.
create function need_point(n needs) returns geography
language sql stable set search_path = public as $$
  select case
    when n.place_id is not null then (select geo from places where id = n.place_id)
    when n.geo is null then null
    when n.author_id = auth.uid() then n.geo
    else st_snaptogrid(n.geo::geometry, 0.003, 0.004)::geography
  end;
$$;

revoke all on function need_point from public;

create function city_needs(
  in_lat      double precision default null,
  in_lng      double precision default null,
  in_radius_m integer default 5000,
  in_need     uuid default null,
  in_mine     boolean default false,
  in_limit    integer default 100
)
returns table (
  id             uuid,
  author_id      uuid,
  author_name    text,
  avatar_url     text,
  body           text,
  place_id       uuid,
  place_title    text,
  latitude       double precision,
  longitude      double precision,
  status         text,
  expires_at     timestamptz,
  created_at     timestamptz,
  response_count integer,
  responded_by_me boolean
)
language sql stable security definer set search_path = public as $$
  select n.id, n.author_id, pr.display_name, pr.avatar_url, n.body,
         n.place_id, coalesce(n.place_title, pl.title),
         st_y(need_point(n)::geometry), st_x(need_point(n)::geometry),
         n.status, n.expires_at, n.created_at,
         (select count(*)::integer from need_responses r where r.need_id = n.id),
         exists (select 1 from need_responses r
                 where r.need_id = n.id and r.author_id = auth.uid())
  from needs n
  join profiles pr on pr.id = n.author_id
  left join places pl on pl.id = n.place_id
  where pr.status <> 'blocked'
    and n.moderation = 'active'
    and not is_hidden_between(auth.uid(), n.author_id)
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and r.target::text = 'need' and r.target_id = n.id
    )
    and (
      (in_need is not null and n.id = in_need)
      or (in_mine and n.author_id = auth.uid())
      or (in_need is null and not in_mine
          and n.status = 'open'
          and (n.expires_at is null or n.expires_at > now())
          and in_lat is not null and in_lng is not null
          and st_dwithin(need_point(n),
                         st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography,
                         least(greatest(in_radius_m, 300), 20000)))
    )
  order by n.created_at desc
  limit least(in_limit, 200);
$$;

create function create_need(
  in_body        text,
  in_place_id    uuid default null,
  in_place_title text default null,
  in_lat         double precision default null,
  in_lng         double precision default null,
  in_expires_at  timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from profiles where id = me and status = 'active') then
    raise exception 'profile_limited' using errcode = 'P0001';
  end if;
  if (in_lat is null) <> (in_lng is null)
     or in_lat not between -90 and 90 or in_lng not between -180 and 180 then
    raise exception 'need_bad_point' using errcode = 'P0001';
  end if;
  if in_expires_at is not null and in_expires_at <= now() then
    raise exception 'need_expired' using errcode = 'P0001';
  end if;

  insert into needs (author_id, body, place_id, place_title, geo, expires_at)
  values (
    me,
    trim(in_body),
    in_place_id,
    nullif(trim(in_place_title), ''),
    case when in_lat is not null
         then st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography end,
    -- Без срока просьба живёт неделю: вечные «ищу» превращают карту в доску
    -- объявлений прошлого года.
    coalesce(in_expires_at, now() + interval '7 days')
  )
  returning id into new_id;
  return new_id;
end;
$$;

create function close_need(in_need uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update needs set status = 'closed', closed_at = now()
   where id = in_need and author_id = auth.uid() and status = 'open';
  if not found and not exists (
    select 1 from needs where id = in_need and author_id = auth.uid()
  ) then
    raise exception 'need_not_yours' using errcode = 'P0001';
  end if;
end;
$$;

create function delete_need(in_need uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from needs where id = in_need and author_id = auth.uid();
  if not found then raise exception 'need_not_yours' using errcode = 'P0001'; end if;
end;
$$;

create function need_respond(in_need uuid, in_body text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  n needs;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into n from needs where id = in_need;
  if not found or is_hidden_between(me, n.author_id) or is_hidden_between(n.author_id, me) then
    raise exception 'need_not_found' using errcode = 'P0001';
  end if;
  if n.author_id = me then raise exception 'need_is_yours' using errcode = 'P0001'; end if;
  if n.status <> 'open' or (n.expires_at is not null and n.expires_at <= now()) then
    raise exception 'need_closed' using errcode = 'P0001';
  end if;

  insert into need_responses (need_id, author_id, body)
  values (in_need, me, nullif(trim(in_body), ''))
  on conflict (need_id, author_id) do update set body = excluded.body;

  perform add_notification(n.author_id, me, 'need_response', 'need', n.id, left(n.body, 120));
end;
$$;

create function need_withdraw_response(in_need uuid) returns void
language sql security definer set search_path = public as $$
  delete from need_responses where need_id = in_need and author_id = auth.uid();
$$;

create function need_responses_list(in_need uuid)
returns table (
  id           uuid,
  author_id    uuid,
  display_name text,
  avatar_url   text,
  body         text,
  created_at   timestamptz
)
language sql stable security definer set search_path = public as $$
  select r.id, r.author_id, p.display_name, p.avatar_url, r.body, r.created_at
  from need_responses r
  join profiles p on p.id = r.author_id
  where r.need_id = in_need
    and p.status <> 'blocked'
    and not is_hidden_between(auth.uid(), r.author_id)
  order by r.created_at
  limit 200;
$$;

revoke all on function city_needs, create_need, close_need, delete_need,
  need_respond, need_withdraw_response, need_responses_list from public;
grant execute on function city_needs, create_need, close_need, delete_need,
  need_respond, need_withdraw_response, need_responses_list to authenticated;

-- ── жалобы (п. 51) ──────────────────────────────────────────────────────────
-- Новые значения перечисления нельзя использовать в той же транзакции, где
-- их добавили, поэтому ниже они сравниваются как текст.

alter type report_target add value if not exists 'quest';
alter type report_target add value if not exists 'need';

create or replace function is_own_report_target(in_target report_target, in_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select case in_target::text
    when 'post'    then exists (select 1 from posts  where id = in_id and author_id = auth.uid())
    when 'event'   then exists (select 1 from events where id = in_id and author_id = auth.uid())
    when 'profile' then in_id = auth.uid()
    when 'place'   then exists (select 1 from places where id = in_id and created_by = auth.uid())
    when 'quest'   then exists (select 1 from quests where id = in_id and author_id = auth.uid())
    when 'need'    then exists (select 1 from needs  where id = in_id and author_id = auth.uid())
    else false
  end;
$$;

-- ── слой активности: квесты и «Мне надо» (п. 5) ─────────────────────────────
-- Та же модель, что в 0016: квест весит как событие (время + участники),
-- просьба — постоянный небольшой вес, пока открыта. Коэффициенты — в
-- activity_config, менять UPDATE'ом.

insert into activity_config (key, value, note) values
  ('w_quest', 3.0, 'базовый вес квеста'),
  ('w_need',  1.0, 'вес открытой просьбы «Мне надо»')
on conflict (key) do nothing;

drop function if exists city_activity(double precision, double precision, integer, text[], text[], timestamptz);

create function city_activity(
  in_lat double precision,
  in_lng double precision,
  in_radius_m integer default 5000,
  in_kinds text[] default array['events', 'places', 'moments', 'quests', 'needs'],
  in_categories text[] default null,
  in_at timestamptz default now()
)
returns table (
  latitude     double precision,
  longitude    double precision,
  score        double precision,
  radius_m     integer,
  event_count  integer,
  place_count  integer,
  moment_count integer,
  quest_count  integer,
  need_count   integer
)
language plpgsql stable security definer set search_path = public as $$
declare
  cfg jsonb;
  center geography := st_setsrid(st_makepoint(in_lng, in_lat), 4326)::geography;
  radius double precision := least(greatest(in_radius_m, 300), 20000);
  cell_m double precision;
  spread_m double precision;
  grid double precision;
begin
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into cfg from activity_config;
  cell_m   := coalesce((cfg ->> 'cell_size_m')::double precision, 600);
  spread_m := coalesce((cfg ->> 'spread_m')::double precision, 450);
  grid := cell_m / cos(radians(in_lat));

  return query
  with objs as (
    select 'e'::text as k, pl.geo as geo,
           coalesce((cfg ->> 'w_event')::double precision, 3)
             * (1 + coalesce((cfg ->> 'w_participant')::double precision, 0.15)
                    * least(coalesce(pc.n, 0), 50))
             * power(0.5, t.dt_h / coalesce((cfg ->> 'half_life_event_h')::double precision, 3)) as w
    from events e
    join places pl on pl.id = e.place_id
    left join lateral (
      select count(*) as n from event_participants ep where ep.event_id = e.id
    ) pc on true
    cross join lateral (
      select case
        when in_at < e.starts_at
          then (extract(epoch from (e.starts_at - in_at)) / 3600.0)::double precision
        when in_at <= coalesce(e.ends_at, e.starts_at + interval '2 hours')
          then 0.0::double precision
        else (extract(epoch from (in_at - coalesce(e.ends_at, e.starts_at + interval '2 hours'))) / 3600.0)::double precision
      end as dt_h
    ) t
    where 'events' = any(in_kinds)
      and e.status = 'active'
      and st_dwithin(pl.geo, center, radius)
      and (in_categories is null or pl.category = any(in_categories))
      and not is_hidden_between(auth.uid(), e.author_id)
      and (case when in_at < e.starts_at
                then t.dt_h <= coalesce((cfg ->> 'event_horizon_h')::double precision, 12)
                else t.dt_h <= coalesce((cfg ->> 'event_past_h')::double precision, 2) end)

    union all

    -- Квест: как событие, но «идёт» до ends_at или до завершения
    -- организатором; долгоживущий квест без ends_at идёт, пока открыт.
    select 'q'::text, coalesce(q.geo, pl.geo),
           coalesce((cfg ->> 'w_quest')::double precision, 3)
             * (1 + coalesce((cfg ->> 'w_participant')::double precision, 0.15)
                    * least(quest_taken_slots(q.id), 50))
             * power(0.5, t.dt_h / coalesce((cfg ->> 'half_life_event_h')::double precision, 3))
    from quests q
    left join places pl on pl.id = q.place_id
    cross join lateral (
      select case
        when in_at < q.starts_at
          then (extract(epoch from (q.starts_at - in_at)) / 3600.0)::double precision
        else 0.0::double precision
      end as dt_h
    ) t
    where 'quests' = any(in_kinds)
      and q.status = 'active'
      and q.moderation = 'active'
      and (q.ends_at is null or q.ends_at > in_at)
      and coalesce(q.geo, pl.geo) is not null
      and st_dwithin(coalesce(q.geo, pl.geo), center, radius)
      and (in_categories is null or pl.category = any(in_categories))
      and not is_hidden_between(auth.uid(), q.author_id)
      and t.dt_h <= coalesce((cfg ->> 'event_horizon_h')::double precision, 12)

    union all

    select 'n'::text, need_point(n), coalesce((cfg ->> 'w_need')::double precision, 1)
    from needs n
    where 'needs' = any(in_kinds)
      and in_categories is null
      and n.status = 'open'
      and n.moderation = 'active'
      and (n.expires_at is null or n.expires_at > in_at)
      and n.created_at <= in_at
      and need_point(n) is not null
      and st_dwithin(need_point(n), center, radius)
      and not is_hidden_between(auth.uid(), n.author_id)

    union all

    select 'm'::text, pl.geo,
           coalesce((cfg ->> 'w_moment')::double precision, 1.5)
             * power(0.5, a.age_h / coalesce((cfg ->> 'half_life_moment_h')::double precision, 6))
    from posts p
    join places pl on pl.id = p.place_id
    cross join lateral (
      select (extract(epoch from (in_at - p.created_at)) / 3600.0)::double precision as age_h
    ) a
    where 'moments' = any(in_kinds)
      and p.status = 'active'
      and p.visibility = 'public'
      and p.show_geo
      and a.age_h between 0 and coalesce((cfg ->> 'moment_max_age_h')::double precision, 36)
      and st_dwithin(pl.geo, center, radius)
      and (in_categories is null or pl.category = any(in_categories))
      and not is_hidden_between(auth.uid(), p.author_id)

    union all

    select 'p'::text, pl.geo, coalesce((cfg ->> 'w_place')::double precision, 0.6)
    from places pl
    where 'places' = any(in_kinds)
      and st_dwithin(pl.geo, center, radius)
      and (in_categories is null or pl.category = any(in_categories))
  ),
  cells as (
    select o.k, o.w, o.geo,
           st_x(st_snaptogrid(st_transform(o.geo::geometry, 3857), grid)) as cx,
           st_y(st_snaptogrid(st_transform(o.geo::geometry, 3857), grid)) as cy
    from objs o
  ),
  cnt as (
    select c.cx, c.cy,
           (count(*) filter (where c.k = 'e'))::integer as ec,
           (count(*) filter (where c.k = 'p'))::integer as pc,
           (count(*) filter (where c.k = 'm'))::integer as mc,
           (count(*) filter (where c.k = 'q'))::integer as qc,
           (count(*) filter (where c.k = 'n'))::integer as nc
    from cells c
    group by c.cx, c.cy
  ),
  centers as (
    select cnt.cx, cnt.cy,
           st_transform(st_setsrid(st_makepoint(cnt.cx, cnt.cy), 3857), 4326)::geography as cg
    from cnt
  ),
  scored as (
    select ce.cx, ce.cy, ce.cg,
           sum(o.w * exp(-power(st_distance(ce.cg, o.geo) / spread_m, 2))) as raw
    from centers ce
    join cells o on st_dwithin(ce.cg, o.geo, spread_m * 2.5)
    group by ce.cx, ce.cy, ce.cg
  ),
  peak as (select coalesce(max(s.raw), 0) as m from scored s)
  select st_y(s.cg::geometry),
         st_x(s.cg::geometry),
         least(1.0, s.raw / greatest(peak.m, coalesce((cfg ->> 'ref_score')::double precision, 6)))::double precision,
         cell_m::integer,
         cnt.ec, cnt.pc, cnt.mc, cnt.qc, cnt.nc
  from scored s
  join cnt on cnt.cx = s.cx and cnt.cy = s.cy
  cross join peak
  where s.raw >= coalesce((cfg ->> 'min_score')::double precision, 0.4)
  order by s.raw desc
  limit 300;
end;
$$;

revoke all on function city_activity from public;
grant execute on function city_activity to authenticated;
