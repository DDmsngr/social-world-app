-- Чаты хранят на сервере только шифротекст. Приватных ключей и открытых
-- сообщений в этой схеме нет.

create table chat_public_keys (
  profile_id          uuid primary key references profiles on delete cascade,
  x25519_public_key   text not null check (length(x25519_public_key) <= 128),
  ed25519_public_key  text not null check (length(ed25519_public_key) <= 128),
  protocol_version    smallint not null default 1 check (protocol_version > 0),
  updated_at          timestamptz not null default now()
);

create table chat_conversations (
  id          uuid primary key default gen_random_uuid(),
  direct_key  text unique,
  created_at  timestamptz not null default now()
);

create table chat_members (
  conversation_id uuid not null references chat_conversations on delete cascade,
  profile_id      uuid not null references profiles on delete cascade,
  joined_at       timestamptz not null default now(),
  last_read_at    timestamptz,
  primary key (conversation_id, profile_id)
);

create table chat_messages (
  id                uuid primary key,
  conversation_id   uuid not null references chat_conversations on delete cascade,
  sender_id         uuid not null references profiles on delete cascade,
  kind              text not null default 'text' check (kind in ('text')),
  ciphertext        text not null check (length(ciphertext) <= 65536),
  nonce             text not null check (length(nonce) <= 64),
  mac               text not null check (length(mac) <= 64),
  signature         text not null check (length(signature) <= 256),
  protocol_version  smallint not null default 1 check (protocol_version > 0),
  sent_at           timestamptz not null default now()
);

create index chat_members_profile_idx
  on chat_members (profile_id, joined_at desc);
create index chat_messages_conversation_idx
  on chat_messages (conversation_id, sent_at);

alter table chat_public_keys enable row level security;
alter table chat_conversations enable row level security;
alter table chat_members enable row level security;
alter table chat_messages enable row level security;

-- Security-definer нужен, чтобы проверки членства не зацикливались на RLS
-- самой таблицы chat_members.
create function is_chat_member(in_conversation uuid)
returns boolean
language sql stable security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from chat_members
    where conversation_id = in_conversation and profile_id = auth.uid()
  );
$$;

revoke all on function is_chat_member from public;
grant execute on function is_chat_member to authenticated;

create policy "публичные ключи видны авторизованным"
  on chat_public_keys for select to authenticated using (true);
create policy "публикую только свои ключи"
  on chat_public_keys for insert to authenticated
  with check (auth.uid() = profile_id);
create policy "обновляю только свои ключи"
  on chat_public_keys for update to authenticated
  using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

create policy "диалог видят только участники"
  on chat_conversations for select to authenticated
  using (is_chat_member(id));

create policy "участников видят только участники диалога"
  on chat_members for select to authenticated
  using (is_chat_member(conversation_id));
create policy "свою отметку чтения обновляю сам"
  on chat_members for update to authenticated
  using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

create policy "сообщения видят только участники"
  on chat_messages for select to authenticated
  using (is_chat_member(conversation_id));
create policy "сообщение пишет участник от своего имени"
  on chat_messages for insert to authenticated
  with check (
    auth.uid() = sender_id and is_chat_member(conversation_id)
  );

-- Создание прямого диалога атомарно: клиент не получает права произвольно
-- добавлять участников в существующие разговоры.
create function create_direct_conversation(in_peer uuid)
returns uuid
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  current_profile uuid := auth.uid();
  pair_key text;
  result_id uuid;
begin
  if current_profile is null then
    raise exception 'authentication required';
  end if;
  if in_peer is null or in_peer = current_profile then
    raise exception 'invalid peer';
  end if;
  if not exists (
    select 1 from profiles where id = in_peer and status = 'active'
  ) then
    raise exception 'peer not found';
  end if;

  pair_key := least(current_profile::text, in_peer::text) || ':' ||
              greatest(current_profile::text, in_peer::text);
  insert into chat_conversations (direct_key)
  values (pair_key)
  on conflict (direct_key) do update set direct_key = excluded.direct_key
  returning id into result_id;

  insert into chat_members (conversation_id, profile_id)
  values (result_id, current_profile), (result_id, in_peer)
  on conflict do nothing;

  return result_id;
end;
$$;

revoke all on function create_direct_conversation from public;
grant execute on function create_direct_conversation to authenticated;

revoke all on chat_public_keys, chat_conversations, chat_members, chat_messages
  from anon, authenticated;
grant select, insert, update on chat_public_keys to authenticated;
grant select on chat_conversations to authenticated;
grant select on chat_members to authenticated;
grant update (last_read_at) on chat_members to authenticated;
grant select, insert on chat_messages to authenticated;

alter publication supabase_realtime add table chat_messages;
