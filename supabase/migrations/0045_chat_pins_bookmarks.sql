-- Закреплённые сообщения и закладки на сообщения.
--
-- Хранятся только id сообщений, не их содержимое: в личных диалогах текст
-- зашифрован, сервер его не видит, и закреп/закладка этого не меняют — текст
-- клиент достаёт и расшифровывает сам.
--
-- Закрепы — общие для чата, их несколько (до 20). Кто закрепляет:
--   * личный диалог — любой из двоих;
--   * группа и канал — только владелец и админы.
-- Закладки — личные, видны только их владельцу.
-- Запись — только через функции (проверка прав на сервере); читать закрепы
-- можно напрямую (нужно для реалтайма), закладки — только через функцию.

-- ── таблицы ─────────────────────────────────────────────────────────────────

create table chat_pins (
  conversation_id uuid not null references chat_conversations on delete cascade,
  message_id      uuid not null references chat_messages on delete cascade,
  pinned_by       uuid not null references profiles on delete cascade,
  pinned_at       timestamptz not null default now(),
  primary key (conversation_id, message_id)
);
create index chat_pins_conversation_idx on chat_pins (conversation_id, pinned_at desc);

create table chat_bookmarks (
  profile_id      uuid not null references profiles on delete cascade,
  message_id      uuid not null references chat_messages on delete cascade,
  conversation_id uuid not null references chat_conversations on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (profile_id, message_id)
);
create index chat_bookmarks_profile_idx on chat_bookmarks (profile_id, created_at desc);

alter table chat_pins enable row level security;
alter table chat_bookmarks enable row level security;
revoke all on chat_pins, chat_bookmarks from public, anon, authenticated;

-- Читать закрепы: участники чата и те, кто может читать публичный канал.
grant select on chat_pins to authenticated;
create policy "закрепы видят читатели чата" on chat_pins
  for select to authenticated
  using (is_chat_member(conversation_id) or can_read_channel(conversation_id));

alter publication supabase_realtime add table chat_pins;

-- ── права ───────────────────────────────────────────────────────────────────

-- Может ли вызывающий закреплять в этом чате.
create function can_pin_in_chat(in_conversation uuid) returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select case
    when c.direct_key is not null then is_chat_member(c.id)
    else coalesce(
      (select m.role in ('owner', 'admin') from chat_members m
        where m.conversation_id = c.id and m.profile_id = auth.uid()),
      false
    )
  end
  from chat_conversations c where c.id = in_conversation;
$$;

-- ── закрепы ─────────────────────────────────────────────────────────────────

create function pin_chat_message(in_message uuid) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid;
begin
  if me is null then raise exception 'authentication required'; end if;
  select m.conversation_id into conv
    from chat_messages m where m.id = in_message and m.deleted_at is null;
  if conv is null then raise exception 'сообщение не найдено'; end if;
  if not can_pin_in_chat(conv) then
    raise exception 'закреплять могут только администраторы';
  end if;
  if (select count(*) from chat_pins p where p.conversation_id = conv) >= 20 then
    raise exception 'слишком много закреплённых сообщений';
  end if;
  insert into chat_pins (conversation_id, message_id, pinned_by)
  values (conv, in_message, me)
  on conflict do nothing;
end;
$$;

create function unpin_chat_message(in_message uuid) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  conv uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select m.conversation_id into conv from chat_messages m where m.id = in_message;
  if conv is null or not can_pin_in_chat(conv) then
    raise exception 'открепить может тот, кто закрепляет';
  end if;
  delete from chat_pins p where p.conversation_id = conv and p.message_id = in_message;
end;
$$;

-- Закрепы чата, свежие первыми. Удалённые у всех сообщения не показываем.
create function chat_pins_list(in_conversation uuid)
returns table (message_id uuid, pinned_by uuid, pinned_at timestamptz)
language sql stable security definer set search_path = public set row_security = off as $$
  select p.message_id, p.pinned_by, p.pinned_at
  from chat_pins p
  join chat_messages m on m.id = p.message_id and m.deleted_at is null
  where p.conversation_id = in_conversation
    and (is_chat_member(in_conversation) or can_read_channel(in_conversation))
  order by p.pinned_at desc;
$$;

-- ── закладки ────────────────────────────────────────────────────────────────

-- Поставить или снять закладку. Возвращает true, если закладка теперь стоит.
create function toggle_chat_bookmark(in_message uuid) returns boolean
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid;
begin
  if me is null then raise exception 'authentication required'; end if;
  select m.conversation_id into conv
    from chat_messages m where m.id = in_message and m.deleted_at is null;
  if conv is null then raise exception 'сообщение не найдено'; end if;
  if not (is_chat_member(conv) or can_read_channel(conv)) then
    raise exception 'not allowed';
  end if;

  delete from chat_bookmarks b where b.profile_id = me and b.message_id = in_message;
  if found then return false; end if;
  insert into chat_bookmarks (profile_id, message_id, conversation_id)
  values (me, in_message, conv);
  return true;
end;
$$;

-- Мои закладки: все или одного чата. Только по живым сообщениям и чатам,
-- куда у меня ещё есть доступ.
create function my_chat_bookmarks(in_conversation uuid default null)
returns table (message_id uuid, conversation_id uuid, created_at timestamptz)
language sql stable security definer set search_path = public set row_security = off as $$
  select b.message_id, b.conversation_id, b.created_at
  from chat_bookmarks b
  join chat_messages m on m.id = b.message_id and m.deleted_at is null
  where b.profile_id = auth.uid()
    and (in_conversation is null or b.conversation_id = in_conversation)
    and (is_chat_member(b.conversation_id) or can_read_channel(b.conversation_id))
  order by b.created_at desc
  limit 500;
$$;

-- ── права на функции ────────────────────────────────────────────────────────

revoke all on function
  can_pin_in_chat(uuid),
  pin_chat_message(uuid),
  unpin_chat_message(uuid),
  chat_pins_list(uuid),
  toggle_chat_bookmark(uuid),
  my_chat_bookmarks(uuid)
from public, anon;

grant execute on function
  can_pin_in_chat(uuid),
  pin_chat_message(uuid),
  unpin_chat_message(uuid),
  chat_pins_list(uuid),
  toggle_chat_bookmark(uuid),
  my_chat_bookmarks(uuid)
to authenticated;
