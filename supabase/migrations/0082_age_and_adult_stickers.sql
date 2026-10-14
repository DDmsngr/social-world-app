-- Возраст и стикеры 18+.
--
-- Дата рождения лежит отдельно от profiles: профили видны всем авторизованным,
-- а возраст человека должен видеть только он сам. Задаётся один раз (исправить
-- можно через поддержку), чтобы подросток не переставил дату после отказа.
--
-- Паки помечаются флагом adult. Тем, кому нет 18 лет или дата ещё не указана,
-- такой пак нельзя поставить (триггер), а приложение не показывает его в
-- магазине, панели и подсказках.

create table profile_ages (
  profile_id uuid primary key references profiles on delete cascade,
  birth_date date not null check (birth_date >= date '1900-01-01'),
  created_at timestamptz not null default now()
);

alter table profile_ages enable row level security;

revoke all on profile_ages from anon, authenticated;
grant select on profile_ages to authenticated;

create policy "возраст: вижу только свой" on profile_ages
  for select to authenticated using (profile_id = auth.uid());

-- Совершеннолетний ли человек. Только для функций базы: клиент свой возраст
-- читает из таблицы, чужой не видит вообще.
create function profile_is_adult(p_profile uuid) returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select exists (
    select 1 from profile_ages
    where profile_id = p_profile
      and birth_date <= (current_date - interval '18 years')::date
  );
$$;

revoke all on function profile_is_adult(uuid) from public, anon, authenticated;

alter table sticker_packs add column adult boolean not null default false;

update sticker_packs set adult = true
where id in ('palych', 'viking', 'stanochnik', 'arturio');

-- Дата рождения: один раз. Повторный вызов ничего не меняет. Если человеку
-- нет 18, ранее поставленные паки 18+ снимаются.
create function set_my_birth_date(p_date date) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Нужно войти в аккаунт' using errcode = '28000';
  end if;
  if p_date is null or p_date > current_date or p_date < current_date - interval '120 years' then
    raise exception 'Неверная дата рождения' using errcode = '22023';
  end if;

  insert into profile_ages (profile_id, birth_date) values (me, p_date)
  on conflict (profile_id) do nothing;

  if not profile_is_adult(me) then
    delete from user_sticker_packs
    where profile_id = me
      and pack_id in (select id from sticker_packs where adult);
  end if;
end;
$$;

revoke all on function set_my_birth_date(date) from public, anon;
grant execute on function set_my_birth_date(date) to authenticated;

-- Пак 18+ не ставится тем, кто не подтвердил возраст.
create function user_sticker_packs_adult_check() returns trigger
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  if exists (select 1 from sticker_packs where id = new.pack_id and adult)
     and not profile_is_adult(new.profile_id) then
    raise exception 'Этот пак только для совершеннолетних' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function user_sticker_packs_adult_check() from public, anon, authenticated;

create trigger user_sticker_packs_adult
  before insert on user_sticker_packs
  for each row execute function user_sticker_packs_adult_check();

-- Каталог с пометкой 18+ (всё остальное — как в 0078).
create or replace function sticker_catalog() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'families', coalesce((select jsonb_object_agg(f.key, to_jsonb(f.words)) from sticker_families f), '{}'::jsonb),
    'packs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'description', p.description,
        'publisher', p.publisher,
        'category', p.category,
        'cover', p.cover_path,
        'version', p.version,
        'status', p.status,
        'adult', p.adult,
        'stickers', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', s.id,
            'emoji', s.emoji,
            'title', s.title,
            'synonyms', to_jsonb(s.synonyms),
            'emotions', to_jsonb(s.emotions),
            'image', s.image_path,
            'thumb', s.thumb_path,
            'w', s.width,
            'h', s.height
          ) order by s.position)
          from stickers s where s.pack_id = p.id
        ), '[]'::jsonb)
      ) order by p.sort_order, p.created_at)
      from sticker_packs p
    ), '[]'::jsonb)
  );
$$;
