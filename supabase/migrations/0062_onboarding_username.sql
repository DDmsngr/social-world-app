-- Онбординг и @ник.
--
-- 1. Город больше не подставляется сам: раньше у колонки был default 'Сочи',
--    и каждый новый человек «жил» в Сочи, не выбирая ничего.
-- 2. onboarded_at — человек прошёл знакомство (имя, город). Пока пусто,
--    приложение показывает онбординг. Имя для этого не годится: вход через
--    VK/Яндекс сразу заполняет его, и знакомство пропускалось.
--    У существующих тоже пусто — пройдут один раз и выберут город.
-- 3. username — @ник. Латиница в нижнем регистре, цифры и _, 3–20 знаков,
--    уникальный. По нику людей ищут, не зная телефона.

alter table profiles alter column city drop default;

alter table profiles add column onboarded_at timestamptz;

alter table profiles add column username text;
alter table profiles add constraint profiles_username_format
  check (username ~ '^[a-z0-9_]{3,20}$');
create unique index profiles_username_key on profiles (username);

grant update (onboarded_at, username) on profiles to authenticated;

-- Поиск людей: «@ник» — по началу ника, иначе по имени или нику. Состав
-- колонок результата сменился, поэтому drop + create и права заново.
drop function search_profiles(text, integer);
create function search_profiles(in_query text, in_limit integer default 10)
returns table (id uuid, display_name text, avatar_url text, username text)
language sql stable security definer set search_path = public as $$
  with q as (
    select trim(in_query) as raw,
           replace(replace(lower(ltrim(trim(in_query), '@')), '%', '\%'), '_', '\_') as nick,
           replace(replace(trim(in_query), '%', '\%'), '_', '\_') as name
  )
  select p.id, p.display_name, p.avatar_url, p.username
  from profiles p, q
  where char_length(q.raw) >= 2
    and p.status <> 'blocked'
    and p.id <> auth.uid()
    and not is_hidden_between(auth.uid(), p.id)
    and (
      p.username like q.nick || '%'
      or (left(q.raw, 1) <> '@' and p.display_name ilike '%' || q.name || '%')
    )
  order by (p.username = lower(ltrim(q.raw, '@'))) desc, p.display_name
  limit least(in_limit, 20);
$$;

revoke all on function search_profiles(text, integer) from public, anon;
grant execute on function search_profiles(text, integer) to authenticated;

-- Карточка профиля теперь с ником.
drop function profile_card(uuid);
create function profile_card(in_profile uuid)
returns table (
  id               uuid,
  display_name     text,
  avatar_url       text,
  bio              text,
  city             text,
  social_score     integer,
  follower_count   bigint,
  following_count  bigint,
  followed_by_me   boolean,
  block_kind       text,
  avatar_video_url text,
  username         text
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
           where b.blocker_id = auth.uid() and b.blocked_id = p.id),
         case when p.premium_until > now() then p.avatar_video_url end,
         p.username
  from profiles p
  where p.id = in_profile
    and p.status <> 'blocked'
    and not exists (
      select 1 from user_blocks b
      where b.blocker_id = p.id and b.blocked_id = auth.uid() and b.kind = 'block'
    );
$$;

revoke all on function profile_card(uuid) from public, anon;
grant execute on function profile_card(uuid) to authenticated;
