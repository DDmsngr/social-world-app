-- Один человек — один аккаунт. Вход через VK и через Яндекс создавал два
-- профиля: мост входа не знал, что это один и тот же человек. Подтверждённый
-- номер (его отдаёт сам провайдер, см. 0040/0067) — надёжный признак: при
-- входе новым способом мост спрашивает, чей это номер, и если у аккаунта он
-- уже есть, привязывает вход к нему, а не заводит новый профиль.
--
-- Только service_role (Edge Function входа). Клиентам хеши номеров не отдаём.

create or replace function profile_by_verified_phone(p_hash text) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  return (
    select profile_id
    from profile_phones
    where phone_hash = phone_hmac(p_hash) and verified
    limit 1
  );
end $$;

revoke all on function profile_by_verified_phone(text) from public, anon, authenticated;
grant execute on function profile_by_verified_phone(text) to service_role;
