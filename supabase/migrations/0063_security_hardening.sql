-- Укрепление прав по аудиту 08.10.2026.
--
-- 1. Служебные функции были вызываемы любым вошедшим пользователем: revoke
--    ... from public не снимает право, которое Supabase выдаёт authenticated
--    напрямую через default privileges. Через add_notification можно было
--    слать поддельные уведомления и пуши от чужого имени, через push_dispatch
--    — флудить пушами. Их зовут только триггеры и pg_cron, все — SECURITY
--    DEFINER от владельца, так что вызывающему право не нужно.
-- 2. Новые функции больше не получают EXECUTE для authenticated сами:
--    каждая миграция обязана явно писать grant execute ... to authenticated
--    (так и принято в проекте).
-- 3. Клиент только читает таблицы баллов, рефералок, звонков, уведомлений —
--    пишут туда функции. Права на запись у authenticated отзываем, чтобы одна
--    ошибочная политика в будущем не открыла возможность рисовать баллы.
-- 4. Одноразовые записи входа через VK/Яндекс (oauth_pkce_state) чистим по
--    расписанию: срок жизни — 10 минут, записи не удалялись.
--
-- spatial_ref_sys (владелец supabase_admin) — отдельным файлом 0063b.

-- 1. Служебные функции
revoke execute on function add_notification from public, anon, authenticated;
revoke execute on function push_dispatch from public, anon, authenticated;
revoke execute on function gc_chat_media from public, anon, authenticated;
revoke execute on function release_scheduled_chat_messages from public, anon, authenticated;

-- 2. Права по умолчанию для новых функций
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres
  revoke execute on functions from public;

-- 3. Таблицы, в которые пишут только функции и триггеры
revoke insert, update, delete, truncate, references, trigger
  on referrals, point_transactions, score_events, referral_settings,
     oauth_identities, notifications, calls
  from anon, authenticated;

-- 4. Уборка записей входа
select cron.schedule(
  'oauth-pkce-cleanup',
  '*/10 * * * *',
  $$delete from public.oauth_pkce_state where created_at < now() - interval '15 minutes'$$
);
