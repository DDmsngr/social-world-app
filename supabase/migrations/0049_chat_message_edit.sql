-- Правка своих сообщений: текст или подпись к вложению.
--
-- В личном диалоге содержимое зашифровано, поэтому клиент сам шифрует новый
-- текст тем же ключом диалога и присылает новый шифротекст, nonce, mac и
-- подпись; сервер их только подменяет. В группах и каналах меняется
-- открытый body. edited_at — пометка «изменено» (карандаш у времени).
-- Реалтайм отдаёт UPDATE строки, клиенты перечитывают сообщение сами.

alter table chat_messages add column if not exists edited_at timestamptz;

create function edit_chat_message(
  in_id uuid,
  in_body text default null,
  in_ciphertext text default null,
  in_nonce text default null,
  in_mac text default null,
  in_signature text default null
) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  msg chat_messages;
  direct boolean;
  stamp timestamptz := now();
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select * into msg from chat_messages where id = in_id for update;
  if msg.id is null or msg.deleted_at is not null then
    raise exception 'сообщение не найдено';
  end if;
  if msg.sender_id <> auth.uid() then
    raise exception 'менять можно только свои сообщения';
  end if;
  if msg.kind in ('voice', 'video_note', 'sticker') then
    raise exception 'такое сообщение не меняется';
  end if;

  select c.direct_key is not null into direct
  from chat_conversations c where c.id = msg.conversation_id;

  if direct then
    if in_ciphertext is null or in_nonce is null or in_mac is null or in_signature is null then
      raise exception 'нужен новый шифротекст';
    end if;
    update chat_messages
       set ciphertext = in_ciphertext, nonce = in_nonce, mac = in_mac,
           signature = in_signature, edited_at = stamp
     where id = in_id;
  else
    if char_length(coalesce(in_body, '')) > 4096 then
      raise exception 'слишком длинное сообщение';
    end if;
    if msg.media is null and coalesce(trim(in_body), '') = '' then
      raise exception 'пустое сообщение';
    end if;
    update chat_messages
       set body = nullif(trim(in_body), ''), edited_at = stamp
     where id = in_id;
  end if;
  return stamp;
end;
$$;

revoke all on function edit_chat_message(uuid, text, text, text, text, text) from public, anon;
grant execute on function edit_chat_message(uuid, text, text, text, text, text) to authenticated;
