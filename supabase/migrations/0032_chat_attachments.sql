-- Вложения в чатах: фото, видео, кружки, голосовые, файлы, стикеры
-- (перенос логики DDChat).
--
-- Файлы лежат в приватном бакете chat-media по пути <conversation_id>/<uuid>.
-- В личных диалогах файл зашифрован на устройстве своим случайным ключом, а
-- ключ и описание файла едут внутри зашифрованного сообщения — сервер видит
-- только тип вложения и шифротекст. В группах описание файла открыто, в
-- колонке media.

-- ── сообщения ───────────────────────────────────────────────────────────────

alter table chat_messages drop constraint chat_messages_kind_check;
alter table chat_messages add constraint chat_messages_kind_check
  check (kind in ('text', 'image', 'video', 'video_note', 'voice', 'file', 'sticker'));

alter table chat_messages
  add column media jsonb check (media is null or pg_column_size(media) <= 4096);

-- Групповое сообщение — текст и/или вложение; личное — только шифротекст.
alter table chat_messages drop constraint chat_messages_payload_check;
alter table chat_messages add constraint chat_messages_payload_check check (
  (ciphertext is null and nonce is null and mac is null and signature is null
    and (body is not null or media is not null))
  or
  (body is null and media is null
    and ciphertext is not null and nonce is not null and mac is not null and signature is not null)
);

-- «Открытое» сообщение теперь определяется отсутствием шифротекста, а не
-- наличием body (у вложения в группе body может не быть).
drop policy chat_messages_can_post on chat_messages;
create policy chat_messages_can_post
  on chat_messages as restrictive for insert to authenticated
  with check (coalesce(chat_can_post(conversation_id, ciphertext is null), false));

-- ── хранилище ───────────────────────────────────────────────────────────────
-- 50 МБ — потолок бесплатного Supabase Cloud на файл.

insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-media', 'chat-media', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

create function chat_media_conversation(object_name text) returns uuid
language sql immutable as $$
  select case
           when (storage.foldername(object_name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           then ((storage.foldername(object_name))[1])::uuid
         end;
$$;

revoke all on function chat_media_conversation from public;
grant execute on function chat_media_conversation to authenticated;

create policy chat_media_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and coalesce(is_chat_member(chat_media_conversation(name)), false)
  );

create policy chat_media_upload
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and coalesce(is_chat_member(chat_media_conversation(name)), false)
    and is_chat_open(chat_media_conversation(name))
  );

-- ── список чатов: тип последнего сообщения для превью ───────────────────────

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
    where x.conversation_id = c.id
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
