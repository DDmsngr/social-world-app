-- Каждый новый пользователь сразу подписан на наш канал «chawo»,
-- а все, кто уже есть, подписываются задним числом. Звонка у канала нет:
-- только счётчик непрочитанного, как при обычной подписке.

create function chawo_autosubscribe() returns trigger
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  ch uuid;
begin
  select id into ch from chat_conversations where is_channel and handle = 'chawo';
  if ch is null then return new; end if;
  insert into chat_members (conversation_id, profile_id) values (ch, new.id)
  on conflict do nothing;
  insert into chat_notification_prefs (profile_id, conversation_id, mode)
  values (new.id, ch, 'off') on conflict do nothing;
  return new;
end;
$$;

revoke all on function chawo_autosubscribe() from public;

create trigger profiles_chawo_autosubscribe
  after insert on profiles
  for each row execute function chawo_autosubscribe();

insert into chat_members (conversation_id, profile_id)
select c.id, p.id
from chat_conversations c cross join profiles p
where c.is_channel and c.handle = 'chawo'
on conflict do nothing;

insert into chat_notification_prefs (profile_id, conversation_id, mode)
select p.id, c.id, 'off'
from chat_conversations c cross join profiles p
where c.is_channel and c.handle = 'chawo'
on conflict do nothing;
