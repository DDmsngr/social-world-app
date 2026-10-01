-- 1. «В сети / был(а) …» в шапке личного чата (макет «Диалог»).
--    Отметку присутствия приложение ставит раз в минуту с 0034; до сих пор она
--    была только для «отправить, когда будет в сети». Теперь её видит
--    собеседник — но только если человек это не выключил (как в Telegram:
--    кто скрыл своё время, сам чужого тоже не видит).
-- 2. Реакции на сообщения (сердечко на макете). Одна реакция от человека на
--    сообщение, повторное нажатие той же — снять. В личных чатах сама реакция
--    видна серверу открытым эмодзи: сквозное шифрование её не закрывает.

-- ── 1. присутствие ──────────────────────────────────────────────────────────

alter table profiles add column show_last_seen boolean not null default true;

create function set_show_last_seen(in_show boolean) returns void
language sql security definer set search_path = public as $$
  update profiles set show_last_seen = coalesce(in_show, true) where id = auth.uid();
$$;

create function my_show_last_seen() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select show_last_seen from profiles where id = auth.uid()), true);
$$;

-- Присутствие собеседника личного чата. null — скрыто (им или мной), не
-- личный чат, блокировка или ни разу не был в приложении.
create function chat_peer_presence(in_conversation uuid)
returns table (online boolean, last_seen timestamptz)
language sql stable security definer set search_path = public set row_security = off as $$
  select p.seen_at > now() - interval '2 minutes',
         -- Точность до минуты: точные секунды — лишняя слежка.
         date_trunc('minute', p.seen_at)
  from chat_conversations c
  join chat_members me on me.conversation_id = c.id and me.profile_id = auth.uid()
  join chat_members peer on peer.conversation_id = c.id and peer.profile_id <> auth.uid()
  join profiles pp on pp.id = peer.profile_id
  join profiles mine on mine.id = auth.uid()
  join user_presence p on p.profile_id = peer.profile_id
  where c.id = in_conversation
    and c.direct_key is not null
    and pp.show_last_seen
    and mine.show_last_seen
    and not chat_is_blocked_pair(auth.uid(), peer.profile_id);
$$;

revoke all on function set_show_last_seen(boolean), my_show_last_seen(),
  chat_peer_presence(uuid) from public, anon;
grant execute on function set_show_last_seen(boolean), my_show_last_seen(),
  chat_peer_presence(uuid) to authenticated;

-- ── 2. реакции ──────────────────────────────────────────────────────────────

create table chat_message_reactions (
  message_id      uuid not null references chat_messages on delete cascade,
  conversation_id uuid not null references chat_conversations on delete cascade,
  profile_id      uuid not null references profiles on delete cascade,
  emoji           text not null check (char_length(emoji) between 1 and 16),
  created_at      timestamptz not null default now(),
  primary key (message_id, profile_id)
);

create index chat_message_reactions_conv_idx on chat_message_reactions (conversation_id);

alter table chat_message_reactions enable row level security;
revoke all on chat_message_reactions from public, anon, authenticated;

-- Читать — участникам чата и читателям публичного канала (нужно реалтайму:
-- он отдаёт изменения только тем, кому видна строка). Писать — только RPC.
grant select on chat_message_reactions to authenticated;
create policy chat_reactions_read on chat_message_reactions
  for select to authenticated
  using (is_chat_member(conversation_id) or can_read_channel(conversation_id));

alter publication supabase_realtime add table chat_message_reactions;

-- Поставить, сменить или снять реакцию. Возвращает текущую реакцию человека
-- на сообщение (null — снята).
create function toggle_chat_reaction(in_message uuid, in_emoji text) returns text
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid;
  current_emoji text;
begin
  if me is null then raise exception 'authentication required'; end if;
  if in_emoji is null or char_length(in_emoji) not between 1 and 16 then
    raise exception 'некорректная реакция';
  end if;
  select m.conversation_id into conv from chat_messages m
  where m.id = in_message and m.deleted_at is null;
  if conv is null or not (is_chat_member(conv) or can_read_channel(conv)) then
    raise exception 'not allowed';
  end if;

  select emoji into current_emoji from chat_message_reactions
  where message_id = in_message and profile_id = me;

  if current_emoji = in_emoji then
    delete from chat_message_reactions where message_id = in_message and profile_id = me;
    return null;
  end if;

  insert into chat_message_reactions (message_id, conversation_id, profile_id, emoji)
  values (in_message, conv, me, in_emoji)
  on conflict (message_id, profile_id) do update
    set emoji = excluded.emoji, created_at = now();
  return in_emoji;
end;
$$;

-- Сводка реакций чата: по сообщению и эмодзи — сколько и моя ли.
create function chat_reactions(in_conversation uuid)
returns table (message_id uuid, emoji text, count integer, mine boolean)
language sql stable security definer set search_path = public set row_security = off as $$
  select r.message_id, r.emoji, count(*)::int, bool_or(r.profile_id = auth.uid())
  from chat_message_reactions r
  where r.conversation_id = in_conversation
    and (is_chat_member(in_conversation) or can_read_channel(in_conversation))
  group by r.message_id, r.emoji
  order by r.message_id, min(r.created_at);
$$;

revoke all on function toggle_chat_reaction(uuid, text), chat_reactions(uuid) from public, anon;
grant execute on function toggle_chat_reaction(uuid, text), chat_reactions(uuid) to authenticated;
