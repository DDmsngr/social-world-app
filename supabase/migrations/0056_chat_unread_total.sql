-- 0056: общее число непрочитанных сообщений человека — для цифры на значке
-- приложения (как у Telegram). Считает так же, как список чатов (my_chats):
-- чужие неудалённые сообщения после последнего прочтения, но не в чатах с
-- режимом «выключено» и не в заглушённых.
--
-- Вызывает только функция push-send под сервисным ключом: клиенту число
-- известно и без неё, а чужое число спрашивать незачем.

create function chat_unread_total(in_profile uuid) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(sum(u.n), 0)::int
  from (
    select (
      select count(*) from chat_messages x
      where x.conversation_id = m.conversation_id
        and x.sender_id <> m.profile_id
        and x.deleted_at is null
        and (m.last_read_at is null or x.sent_at > m.last_read_at)
    ) as n
    from chat_members m
    left join chat_notification_prefs p
      on p.conversation_id = m.conversation_id and p.profile_id = m.profile_id
    where m.profile_id = in_profile
      and coalesce(p.mode, 'sound') <> 'off'
      and (p.muted_until is null or p.muted_until <= now())
  ) u;
$$;

revoke all on function chat_unread_total(uuid) from public, anon, authenticated;
grant execute on function chat_unread_total(uuid) to service_role;
