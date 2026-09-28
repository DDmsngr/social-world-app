-- Системное исправление находки 27.09 (см. память проекта): self-hosted
-- Supabase при поднятии стека выставляет
--   alter default privileges in schema public grant execute on functions
--     to postgres, anon, authenticated, service_role;
-- (и то же для tables/sequences). Это право выдаётся НАПРЯМУЮ ролям в момент
-- СОЗДАНИЯ объекта. Приём «revoke all on X from public», которым пользуются
-- миграции 0001–0026, снимает права только у псевдо-роли PUBLIC и не трогает
-- то, что уже выдано anon/authenticated отдельно от неё.
--
-- Для ТАБЛИЦ это не привело к утечке: RLS-политики везде написаны
-- `for ... to authenticated` (проверено запросом к pg_policies — политик без
-- явной роли, то есть открытых для public/anon, в схеме нет ни одной), так
-- что anon получал ноль строк, даже имея сам грант. Ревокаем эти таблицы
-- ниже просто для гигиены — чтобы будущая неосторожная политика без
-- "to authenticated" не открыла дыру молча.
--
-- Для ФУНКЦИЙ утечка настоящая: большинство читающих функций написаны как
-- `security definer` и либо не проверяют auth.uid() вовсе (city_feed,
-- city_events, city_activity, nearby_places, place_by_id, route_detail,
-- profile_card, search_profiles, post_comments_tree, event_participants_list,
-- quests_list, city_needs), либо просто отдают пустой результат анониму
-- (my_saved, my_blocks, my_notifications) — но САМ ВЫЗОВ был доступен без
-- единого исключения любому, у кого есть anon-ключ. Ключ не секрет по
-- дизайну Supabase (лежит в каждом APK) — защищать он не обязан ничего сам
-- по себе, но и не должен быть единственной преградой между анонимом и
-- всем публичным контентом сервиса.
--
-- Ровно две функции нарочно оставлены анониму — обе уже несли явный
-- `grant ... to anon` (это и есть признак, что решение было осознанным, не
-- забытым revoke): вход по приглашению в командную панель происходит ДО
-- входа в систему.
--   ws_invitation_preview        — посмотреть, на что пригласили;
--   ws_register_via_invitation   — завести аккаунт по токену приглашения.
-- Обе проверены: сами по себе не открывают ничего, кроме одного письма
-- приглашения по одноразовому токену (or создают ровно тот аккаунт, что в
-- этом приглашении указан).
--
-- Revoke от authenticated НЕ делаем: это штатный вызывающий почти для всей
-- схемы, массовый отзыв сломал бы приложение целиком.

revoke execute on all functions in schema public from anon;

grant execute on function ws_invitation_preview(text) to anon;
grant execute on function ws_register_via_invitation(text, text) to anon;

-- Таблицы: гигиена по итогам аудита 27.09 (has_table_privilege('anon', …)
-- было true у всех 21 штуки ниже, при нуле подходящих RLS-политик под anon).
revoke all on
  activity_config, comment_likes, event_participants, events, follows,
  locations, notifications, oauth_identities, oauth_pkce_state, places,
  post_comments, post_likes, posts, profiles, reports, route_photos,
  routes, saved_items, score_events, user_blocks, ws_app_releases
from anon;

-- На будущее: новая функция или таблица без явного grant не должна снова
-- открыться анониму тем же способом. Действует для объектов, которые
-- создаёт роль postgres — а миграции всегда накатываются как postgres.
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke all on tables from anon;
