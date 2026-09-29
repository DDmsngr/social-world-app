-- Push-уведомления (FCM). База только ставит задачу: триггер отправляет в
-- Edge Function `push-send` идентификатор события, а та сама собирает текст,
-- находит получателей и ходит в FCM. Так в базе нет ни ключа FCM, ни сетевых
-- таймаутов в транзакции (pg_net шлёт асинхронно, после коммита).
--
-- Адрес функции и общий секрет лежат в Vault, а не в миграции — при возврате
-- на self-hosted меняется только значение `push_function_url`:
--   select vault.create_secret('https://<проект>/functions/v1/push-send', 'push_function_url');
--   select vault.create_secret('<случайная строка>', 'push_webhook_secret');
-- Тот же секрет — в секретах Edge Functions как PUSH_WEBHOOK_SECRET.

create extension if not exists pg_net with schema extensions;

-- ── токены устройств ────────────────────────────────────────────────────────
-- Несколько устройств на человека (в DDChat был один токен на пользователя, и
-- второй телефон молча переставал получать пуши).

create table push_tokens (
  token      text primary key check (char_length(token) between 20 and 4096),
  profile_id uuid not null references profiles on delete cascade,
  platform   text not null default 'android' check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);

create index push_tokens_profile_idx on push_tokens (profile_id, updated_at desc);

alter table push_tokens enable row level security;
revoke all on push_tokens from anon, authenticated;

-- Токен привязан к устройству, а не к аккаунту: вошёл другой человек на том
-- же телефоне — токен переходит к нему. Больше 10 устройств не держим.
create function register_push_token(in_token text, in_platform text default 'android')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  insert into push_tokens (token, profile_id, platform)
  values (in_token, auth.uid(), in_platform)
  on conflict (token) do update
    set profile_id = excluded.profile_id,
        platform   = excluded.platform,
        updated_at = now();

  delete from push_tokens
  where profile_id = auth.uid()
    and token not in (
      select token from push_tokens
      where profile_id = auth.uid()
      order by updated_at desc limit 10
    );
end;
$$;

-- Вызывается перед выходом из аккаунта: иначе пуши прежнего владельца
-- продолжили бы приходить на телефон.
create function unregister_push_token(in_token text)
returns void
language sql security definer set search_path = public as $$
  delete from push_tokens where token = in_token and profile_id = auth.uid();
$$;

revoke all on function register_push_token, unregister_push_token from public;
grant execute on function register_push_token, unregister_push_token to authenticated;

-- ── отправка ────────────────────────────────────────────────────────────────

create function push_dispatch(payload jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  fn_url text;
  fn_secret text;
begin
  select decrypted_secret into fn_url
  from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into fn_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if fn_url is null or fn_secret is null then return; end if;

  perform net.http_post(
    url := fn_url,
    body := payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', fn_secret
    ),
    timeout_milliseconds := 10000
  );
exception when others then
  -- Пуш — не повод откатывать сообщение или уведомление.
  raise warning 'push_dispatch: %', sqlerrm;
end;
$$;

create function trg_push_chat_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform push_dispatch(jsonb_build_object('type', 'message', 'message_id', new.id));
  return null;
end;
$$;

create trigger push_on_chat_message after insert on chat_messages
  for each row execute function trg_push_chat_message();

create function trg_push_notification() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform push_dispatch(jsonb_build_object('type', 'notification', 'notification_id', new.id));
  return null;
end;
$$;

create trigger push_on_notification after insert on notifications
  for each row execute function trg_push_notification();

-- Ванильный Postgres даёт PUBLIC право выполнять новую функцию (см. 0027/0028);
-- триггерным функциям 0030 и этой миграции оно ни к чему.
revoke all on function push_dispatch, trg_push_chat_message, trg_push_notification,
  chat_messages_server_time, chat_messages_rate_limit from public;
