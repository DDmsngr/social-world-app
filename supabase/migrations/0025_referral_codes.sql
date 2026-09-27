-- Реферальный QR у мест: статичный код на стикере, который считает, сколько
-- установок привело конкретное место (кафе, магазин).
--
-- Не путать с QR прибытия на квест (0023, `quests.arrival_code`): там код
-- открывается внутри уже установленного приложения и подтверждает участие в
-- конкретном квесте с лимитом мест. Здесь QR ведёт человека БЕЗ приложения —
-- сначала на страницу «скачать», а награду (кофе на кассе) кассир выдаёт на
-- глаз, тем же способом, что и с бумажным купоном. Код нужен только для
-- статистики «сколько установок принесло это место», не для выдачи награды.
--
-- Управление кодами (создание, чтение статистики) — только из psql: своей
-- админ-панели пока нет (ТЗ п. 115 не входит в этот этап), функции без
-- grant выполняются лишь под ролью postgres.

create table referral_codes (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique check (code = upper(code)),
  label      text not null check (char_length(label) between 1 and 200),
  place_id   uuid references places on delete set null,
  created_at timestamptz not null default now()
);

alter table referral_codes enable row level security;
revoke all on referral_codes from anon, authenticated;

create table referral_signups (
  referral_code_id uuid not null references referral_codes on delete cascade,
  profile_id       uuid not null references profiles on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (referral_code_id, profile_id)
);

alter table referral_signups enable row level security;
revoke all on referral_signups from anon, authenticated;

-- Записывает переход по коду. Идемпотентно: повторная ссылка от того же
-- человека не плодит вторую строку — `on conflict do nothing`.
--
-- Код не защищён от перебора отдельно (нет rate limit): цена ошибки —
-- неверная цифра в статистике одного места, не выдача награды и не доступ
-- к чужим данным, поэтому лишняя защита здесь не оправдана.
create function record_referral_signup(in_code text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rid uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select id into rid from referral_codes where code = upper(trim(in_code));
  if rid is null then
    raise exception 'referral_not_found' using errcode = 'P0001';
  end if;
  insert into referral_signups (referral_code_id, profile_id)
  values (rid, me)
  on conflict do nothing;
end;
$$;

revoke all on function record_referral_signup from public;
grant execute on function record_referral_signup to authenticated;

-- Новый код для места. Пример из psql:
--   select create_referral_code('Кофе у Серёги, Навагинская 12');
create function create_referral_code(in_label text, in_place_id uuid default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  new_code text;
begin
  loop
    -- 6 символов без похожих друг на друга (0/O, 1/I/L) — та же азбука, что
    -- у arrival_code квеста (0023). Байты 0–5 из UUID v4 не задевают байты
    -- версии/варианта (6 и 8), так что смещать индексы не нужно.
    select string_agg(
             substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + get_byte(r.b, i) % 31, 1),
             '' order by i)
      into new_code
    from (select uuid_send(gen_random_uuid()) as b) r
    cross join unnest(array[0, 1, 2, 3, 4, 5]) as i;
    exit when not exists (select 1 from referral_codes where code = new_code);
  end loop;

  insert into referral_codes (code, label, place_id) values (new_code, trim(in_label), in_place_id);
  return new_code;
end;
$$;

revoke all on function create_referral_code from public;

-- Статистика по всем кодам. Пример: select * from referral_stats();
create function referral_stats()
returns table (code text, label text, place_id uuid, signups bigint, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select rc.code, rc.label, rc.place_id, count(rs.profile_id), rc.created_at
  from referral_codes rc
  left join referral_signups rs on rs.referral_code_id = rc.id
  group by rc.id
  order by rc.created_at desc;
$$;

revoke all on function referral_stats from public;
