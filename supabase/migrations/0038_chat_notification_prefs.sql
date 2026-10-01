-- Как чат беспокоит человека: со звуком, только вибрация, тихо, выключен,
-- «выключить на…». Решает сервер (push-send), потому что пуш в свёрнутом
-- приложении рисует сама система — клиент его не видит и отфильтровать не
-- может. Строка есть только у чатов с нестандартным режимом.

create table chat_notification_prefs (
  profile_id      uuid not null references profiles on delete cascade,
  conversation_id uuid not null references chat_conversations on delete cascade,
  mode            text not null default 'sound'
                  check (mode in ('sound', 'vibrate', 'silent', 'off')),
  muted_until     timestamptz,
  updated_at      timestamptz not null default now(),
  primary key (profile_id, conversation_id)
);

-- Читать и писать — только через функции; push-send ходит с service_role.
alter table chat_notification_prefs enable row level security;
revoke all on chat_notification_prefs from public, anon, authenticated;

create function set_chat_notification(
  p_conversation uuid, p_mode text, p_muted_until timestamptz default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if not exists (
    select 1 from chat_members
    where conversation_id = p_conversation and profile_id = auth.uid()
  ) then
    raise exception 'вы не участник этого чата';
  end if;
  if p_mode not in ('sound', 'vibrate', 'silent', 'off') then
    raise exception 'неизвестный режим';
  end if;

  -- Режим по умолчанию без таймера — это отсутствие строки.
  if p_mode = 'sound' and (p_muted_until is null or p_muted_until <= now()) then
    delete from chat_notification_prefs
    where profile_id = auth.uid() and conversation_id = p_conversation;
    return;
  end if;

  insert into chat_notification_prefs (profile_id, conversation_id, mode, muted_until)
  values (auth.uid(), p_conversation, p_mode,
          case when p_muted_until > now() then p_muted_until end)
  on conflict (profile_id, conversation_id) do update
    set mode = excluded.mode, muted_until = excluded.muted_until, updated_at = now();
end $$;

-- Все мои настройки разом: список чатов рисует 🔕 без запроса на каждый чат.
create function my_chat_notifications()
returns table (conversation_id uuid, mode text, muted_until timestamptz)
language sql stable security definer set search_path = public as $$
  select p.conversation_id, p.mode,
         case when p.muted_until > now() then p.muted_until end
  from chat_notification_prefs p
  where p.profile_id = auth.uid();
$$;

revoke all on function set_chat_notification(uuid, text, timestamptz),
  my_chat_notifications() from public, anon;
grant execute on function set_chat_notification(uuid, text, timestamptz),
  my_chat_notifications() to authenticated;
