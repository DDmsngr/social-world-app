-- 1. Статус прочтения в списке чатов: my_chats отдаёт last_read — прочитал ли
--    последнее сообщение кто-то, кроме автора. Для личных клиент считал это и
--    раньше по peer_last_read_at, для групп данных не было.
-- 2. Уборка файлов chat-media, которые больше никому не принадлежат: группа
--    удалена (ушёл последний участник) или сообщение группы удалено у всех.
--    Строки уходят каскадом, а файлы в хранилище оставались навсегда.
--    Удалять объекты прямым SQL Supabase не даёт — только через Storage API,
--    поэтому пути копятся в очереди, а раз в 10 минут pg_cron зовёт Edge
--    Function chat-media-gc, которая удаляет их сервисным ключом.
--    Файлы личных диалогов сюда не попадают: их путь лежит внутри
--    шифротекста, свой файл автор удаляет сам (0033).

-- ── 1. my_chats + last_read ─────────────────────────────────────────────────

drop function my_chats(uuid);

create function my_chats(in_conversation uuid default null)
returns table (
  id                uuid,
  kind              text,
  title             text,
  member_count      integer,
  my_role           text,
  closed            boolean,
  peer_id           uuid,
  peer_name         text,
  peer_avatar       text,
  peer_last_read_at timestamptz,
  last_id           uuid,
  last_kind         text,
  last_sender_id    uuid,
  last_sender_name  text,
  last_sent_at      timestamptz,
  last_body         text,
  last_ciphertext   text,
  last_nonce        text,
  last_mac          text,
  last_signature    text,
  unread_count      integer,
  last_read         boolean
)
language sql stable security definer set search_path = public set row_security = off as $$
  select c.id,
         case when c.direct_key is not null then 'direct'
              when c.quest_id is not null then 'quest'
              else 'group' end,
         coalesce(c.title, q.title),
         (select count(*)::int from chat_members m2 where m2.conversation_id = c.id),
         me.role,
         c.closed_at is not null,
         peer.profile_id, pp.display_name, pp.avatar_url, peer.last_read_at,
         lm.id, lm.kind, lm.sender_id, sp.display_name, lm.sent_at,
         lm.body, lm.ciphertext, lm.nonce, lm.mac, lm.signature,
         (select count(*)::int from chat_messages x
           where x.conversation_id = c.id and x.sender_id <> me.profile_id
             and x.deleted_at is null
             and (me.last_read_at is null or x.sent_at > me.last_read_at)),
         lm.id is not null and exists (
           select 1 from chat_members r
           where r.conversation_id = c.id
             and r.profile_id <> lm.sender_id
             and r.last_read_at >= lm.sent_at
         )
  from chat_members me
  join chat_conversations c on c.id = me.conversation_id
  left join quests q on q.id = c.quest_id
  left join lateral (
    select m.profile_id, m.last_read_at from chat_members m
    where c.direct_key is not null and m.conversation_id = c.id and m.profile_id <> me.profile_id
    limit 1
  ) peer on true
  left join profiles pp on pp.id = peer.profile_id
  left join lateral (
    select x.* from chat_messages x
    where x.conversation_id = c.id and x.deleted_at is null
    order by x.sent_at desc limit 1
  ) lm on true
  left join profiles sp on sp.id = lm.sender_id
  where me.profile_id = auth.uid()
    and (in_conversation is null or c.id = in_conversation)
    and (in_conversation is not null or not (c.direct_key is not null and lm.id is null))
  order by coalesce(lm.sent_at, c.created_at) desc;
$$;

revoke all on function my_chats from public;
grant execute on function my_chats to authenticated;

-- ── 2. очередь на удаление файлов ───────────────────────────────────────────

create table chat_media_trash (
  path      text primary key,
  queued_at timestamptz not null default now()
);

alter table chat_media_trash enable row level security;
revoke all on chat_media_trash from public, anon, authenticated;

-- Группа удаляется — все её файлы в очередь.
create function trg_chat_media_trash_conversation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into chat_media_trash (path)
  select o.name from storage.objects o
  where o.bucket_id = 'chat-media' and o.name like old.id::text || '/%'
  on conflict do nothing;
  return old;
end;
$$;

create trigger chat_media_trash_on_conversation_delete
  before delete on chat_conversations
  for each row execute function trg_chat_media_trash_conversation();

-- Сообщение группы удалено у всех — его файл в очередь.
create function trg_chat_media_trash_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.deleted_at is null and new.deleted_at is not null
     and old.media ? 'path' then
    insert into chat_media_trash (path) values (old.media ->> 'path')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger chat_media_trash_on_message_delete
  before update of deleted_at on chat_messages
  for each row execute function trg_chat_media_trash_message();

-- Будильник для Edge Function. Адрес — соседний с push-send (тот же проект,
-- тот же общий секрет из Vault, см. 0031).
create function gc_chat_media() returns void
language plpgsql security definer set search_path = public as $$
declare
  fn_url text;
  fn_secret text;
begin
  if not exists (select 1 from chat_media_trash) then return; end if;
  select replace(decrypted_secret, '/push-send', '/chat-media-gc') into fn_url
  from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into fn_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if fn_url is null or fn_secret is null then return; end if;

  perform net.http_post(
    url := fn_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', fn_secret),
    timeout_milliseconds := 30000
  );
end;
$$;

revoke all on function trg_chat_media_trash_conversation, trg_chat_media_trash_message,
  gc_chat_media from public;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'gc-chat-media';
    perform cron.schedule('gc-chat-media', '*/10 * * * *', 'select gc_chat_media()');
  else
    raise notice 'pg_cron не включён: задачу gc-chat-media поставить вручную';
  end if;
end $$;
