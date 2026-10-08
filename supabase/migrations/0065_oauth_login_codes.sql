-- Вход через VK ID / Яндекс ID: сессия больше не едет в ссылке приложения.
--
-- Раньше сервер редиректил в приложение на socialworld://auth-callback#
-- refresh_token=..., а приложение принимало любую такую ссылку. Её мог
-- перехватить любой, кто зарегистрировал схему socialworld, а чужую ссылку с
-- токеном злоумышленника приложение молча принимало: человек оказывался в чужом
-- аккаунте.
--
-- Теперь приложение перед входом придумывает одноразовый секрет и передаёт
-- серверу только его хеш (app_challenge). После входа сервер кладёт короткоживущий
-- код (oauth_login_codes) и редиректит в приложение только с кодом. Приложение
-- меняет код + секрет на сессию в oauth-exchange. Без секрета код бесполезен,
-- а токены нигде не хранятся: сессия выпускается в момент обмена.

alter table oauth_pkce_state add column app_challenge text;

create table oauth_login_codes (
  code        text primary key,
  provider    text not null,
  external_id text not null,
  challenge   text not null,
  created_at  timestamptz not null default now()
);

alter table oauth_login_codes enable row level security;
revoke all on oauth_login_codes from public, anon, authenticated;
grant select, insert, delete on oauth_login_codes to service_role;

-- Чистка: коды живут 2 минуты, записи входа — 10 (в коде функций проверяется,
-- здесь только уборка мусора).
select cron.schedule(
  'oauth-pkce-cleanup',
  '*/10 * * * *',
  $$delete from public.oauth_pkce_state where created_at < now() - interval '15 minutes';
    delete from public.oauth_login_codes where created_at < now() - interval '10 minutes'$$
);
