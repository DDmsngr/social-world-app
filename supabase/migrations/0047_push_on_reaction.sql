-- Пуш автору сообщения, когда на него поставили реакцию (или сменили).
-- Снятие реакции пуша не даёт. Текст сообщения в пуш не попадает: в личных
-- он зашифрован, сервер его не знает.

create function trg_push_chat_reaction() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.emoji = new.emoji then
    return null;
  end if;
  perform push_dispatch(jsonb_build_object(
    'type', 'reaction',
    'message_id', new.message_id,
    'profile_id', new.profile_id
  ));
  return null;
end;
$$;

create trigger push_on_chat_reaction after insert or update of emoji on chat_message_reactions
  for each row execute function trg_push_chat_reaction();

revoke all on function trg_push_chat_reaction() from public;
