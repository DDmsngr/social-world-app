-- Подтверждённый номер телефона: приходит от Яндекс ID / VK ID при входе
-- (право login:default_phone / phone), а не вводится человеком. Подтверждённый
-- номер сильнее самозаявленного: если кто-то вписал чужой номер руками,
-- настоящий владелец при входе через Яндекс или VK забирает его себе.
-- Хеш считает Edge Function того же вида, что и клиент (SHA-256 от цифр,
-- 8… → 7…), сам номер нигде не хранится.

alter table profile_phones add column verified boolean not null default false;

-- Только service_role (Edge Function входа). Возвращает true, если номер записан.
create function set_verified_phone(p_profile uuid, p_hash text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'некорректный номер';
  end if;

  -- Чужой самозаявленный номер уступает подтверждённому; чужой подтверждённый
  -- — нет (один и тот же номер подтвердили два аккаунта: остаётся первый).
  delete from profile_phones
  where phone_hash = p_hash and profile_id <> p_profile and not verified;
  if exists (select 1 from profile_phones where phone_hash = p_hash and profile_id <> p_profile) then
    return false;
  end if;

  insert into profile_phones (profile_id, phone_hash, verified)
  values (p_profile, p_hash, true)
  on conflict (profile_id) do update
    set phone_hash = excluded.phone_hash, verified = true;
  return true;
end $$;

revoke all on function set_verified_phone(uuid, text) from public, anon, authenticated;
grant execute on function set_verified_phone(uuid, text) to service_role;

-- Самозаявленный номер не может перебить свой же подтверждённый.
create or replace function set_my_phone(p_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'некорректный номер';
  end if;
  if exists (select 1 from profile_phones where profile_id = auth.uid() and verified) then
    raise exception 'номер уже подтверждён через вход, менять его нельзя';
  end if;
  insert into profile_phones (profile_id, phone_hash, verified)
  values (auth.uid(), p_hash, false)
  on conflict (profile_id) do update set phone_hash = excluded.phone_hash;
exception when unique_violation then
  raise exception 'этот номер уже привязан к другому профилю';
end $$;

-- Подтверждённый номер убрать нельзя: он связан со входом.
create or replace function clear_my_phone() returns void
language sql security definer set search_path = public as $$
  delete from profile_phones where profile_id = auth.uid() and not verified;
$$;

-- none | self | verified — для плашки на экране приглашений.
create function my_phone_status() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case when verified then 'verified' else 'self' end
       from profile_phones where profile_id = auth.uid()),
    'none');
$$;

-- Какие входы привязаны к аккаунту: от этого зависит, какую кнопку
-- «Подтвердить через …» показывать (повторный вход чужим провайдером создал
-- бы другой аккаунт).
create function my_oauth_providers() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(provider order by provider), '{}')
  from oauth_identities where profile_id = auth.uid();
$$;

revoke all on function my_phone_status(), my_oauth_providers() from public, anon;
grant execute on function my_phone_status(), my_oauth_providers() to authenticated;

-- В выдаче сверки подтверждённые номера помечаются: клиент может выше
-- ранжировать надёжных знакомых.
drop function match_contacts(text[]);
create function match_contacts(p_hashes text[])
returns table (phone_hash text, id uuid, display_name text, avatar_url text, followed_by_me boolean, verified boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if coalesce(array_length(p_hashes, 1), 0) > 5000 then
    raise exception 'слишком много контактов за раз';
  end if;
  return query
  select ph.phone_hash, p.id, coalesce(p.display_name, 'Без имени'), p.avatar_url,
         exists (
           select 1 from follows f
           where f.follower_id = auth.uid()
             and f.target_type = 'profile' and f.target_id = p.id
         ),
         ph.verified
  from profile_phones ph
  join profiles p on p.id = ph.profile_id
  where ph.phone_hash = any (p_hashes)
    and p.id <> auth.uid()
    and p.status <> 'blocked';
end $$;

revoke all on function match_contacts(text[]) from public, anon;
grant execute on function match_contacts(text[]) to authenticated;
