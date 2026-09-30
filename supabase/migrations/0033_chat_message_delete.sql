-- Удаление сообщений в чатах «у всех».
--
-- Удаление мягкое: строка остаётся «надгробием» — id, автор, время, пометка
-- deleted_at, а содержимое (текст, шифротекст, описание файла) стирается.
-- Жёсткий delete не годится: realtime не умеет фильтровать события удаления
-- по conversation_id, и у собеседника сообщение не пропадало бы, пока он не
-- переоткроет чат. Обновление строки приходит в поток обычным путём.
--
-- Правила: своё сообщение автор удаляет у всех всегда, без ограничения по
-- времени; владелец группы — любое сообщение своей группы (модерация). Чужое
-- в личном диалоге у всех не удалить — только скрыть у себя (это делает
-- клиент, на сервер не ходит).
--
-- Файл вложения удаляет клиент: в личных диалогах путь лежит внутри
-- шифротекста, и сервер его не знает.

alter table chat_messages add column deleted_at timestamptz;

alter table chat_messages drop constraint chat_messages_payload_check;
alter table chat_messages add constraint chat_messages_payload_check check (
  (deleted_at is not null
    and body is null and media is null
    and ciphertext is null and nonce is null and mac is null and signature is null)
  or
  (deleted_at is null and (
    (ciphertext is null and nonce is null and mac is null and signature is null
      and (body is not null or media is not null))
    or
    (body is null and media is null
      and ciphertext is not null and nonce is not null and mac is not null and signature is not null)
  ))
);

create function delete_chat_messages(in_ids uuid[])
returns setof uuid
language sql security definer set search_path = public as $$
  update chat_messages m
     set deleted_at = now(),
         body = null, media = null,
         ciphertext = null, nonce = null, mac = null, signature = null
   where m.id = any(in_ids)
     and m.deleted_at is null
     and (
       m.sender_id = auth.uid()
       or exists (
         select 1
         from chat_members me
         join chat_conversations c on c.id = me.conversation_id
         where me.conversation_id = m.conversation_id
           and me.profile_id = auth.uid()
           and me.role = 'owner'
           and c.direct_key is null
       )
     )
  returning m.id;
$$;

revoke all on function delete_chat_messages from public;
grant execute on function delete_chat_messages to authenticated;

-- Свои файлы в chat-media автор может удалить (раньше удаления не было
-- вообще, и уборка после неудачной отправки молча не срабатывала).
create policy chat_media_delete_own
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media' and owner = auth.uid());

-- Список чатов: удалённое не становится «последним сообщением» и не
-- считается непрочитанным.
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
  unread_count      integer
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
             and (me.last_read_at is null or x.sent_at > me.last_read_at))
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
