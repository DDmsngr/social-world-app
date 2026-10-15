-- Аудит 15.10.2026, п. 3: автопривязка входа по номеру телефона.
--
-- Вход через VK или Яндекс сам привязывается к аккаунту с тем же подтверждённым
-- номером. Если оператор отдал старый номер другому человеку, тот, войдя через
-- VK с этим номером, попадал в чужой давно брошенный аккаунт (а с ним в копии
-- ключей и переписку). Теперь привязка работает, только пока аккаунт живой:
-- последняя активность (присутствие, последний вход) не старше 180 дней. У
-- брошенного аккаунта функция отвечает «ничей», вход заводит новый профиль.

create or replace function profile_by_verified_phone(p_hash text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  owner uuid;
  last_active timestamptz;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select profile_id into owner
    from profile_phones
   where phone_hash = phone_hmac(p_hash) and verified
   limit 1;
  if owner is null then
    return null;
  end if;
  select greatest(
           (select seen_at from user_presence where profile_id = owner),
           (select last_sign_in_at from auth.users where id = owner),
           (select created_at from auth.users where id = owner) )
    into last_active;
  if last_active is null or last_active < now() - interval '180 days' then
    return null;
  end if;
  return owner;
end $$;

revoke all on function profile_by_verified_phone(text) from public, anon, authenticated;
grant execute on function profile_by_verified_phone(text) to service_role;
