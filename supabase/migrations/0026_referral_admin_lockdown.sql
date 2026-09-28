-- Исправление 0025: `create_referral_code` и `referral_stats` должны быть
-- доступны только из psql (под ролью postgres), но были вызываемы любым
-- вошедшим пользователем через обычный RPC.
--
-- Причина: у self-hosted Supabase в схеме public действует
-- `alter default privileges ... grant execute on functions to authenticated`,
-- выставленный при поднятии стека. Он выдаёт право на выполнение НАПРЯМУЮ
-- роли authenticated в момент создания функции — «revoke all ... from
-- public» снимает права только у псевдо-роли PUBLIC и никак не трогает уже
-- выданное authenticated. Для таблиц это неважно: там миграции с самого
-- начала называли роли явно («revoke all on X from anon, authenticated»),
-- а для этих двух функций я по ошибке скопировал более короткую форму,
-- которая годится только когда следом идёт свой grant (как у
-- record_referral_signup).
--
-- Проверено на боевой базе в открытой транзакции с откатом (см. память):
-- до этой миграции `select create_referral_code(...)` и `select *
-- from referral_stats()` проходили под `set local role authenticated`.

revoke all on function create_referral_code(text, uuid) from public, anon, authenticated;
revoke all on function referral_stats() from public, anon, authenticated;
