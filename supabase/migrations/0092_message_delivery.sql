-- «Доставлено»: у отправителя две серые галочки, когда сообщение дошло до
-- телефона получателя, и красные, когда прочитано (раньше были только
-- «ушло» и «прочитано»).
--
-- Телефон получателя при загрузке списка чатов и открытом чате зовёт
-- mark_delivered(): все его личные диалоги, где есть чужие сообщения новее
-- прежней отметки, получают last_delivered_at = now(). Сообщение доставлено,
-- если sent_at не позже отметки собеседника, как и у last_read_at.
-- Только личные диалоги: у групп и каналов «доставлено» не имеет смысла.

alter table chat_members add column last_delivered_at timestamptz;

create function mark_delivered() returns void
language sql
security definer
set search_path = public
as $$
  update chat_members m
     set last_delivered_at = now()
   where m.profile_id = auth.uid()
     and exists (select 1 from chat_conversations c
                  where c.id = m.conversation_id and c.direct_key is not null)
     and exists (select 1 from chat_messages x
                  where x.conversation_id = m.conversation_id
                    and x.sender_id <> m.profile_id
                    and x.sent_at > coalesce(m.last_delivered_at, '-infinity'));
$$;

revoke all on function mark_delivered() from public, anon;
grant execute on function mark_delivered() to authenticated;
