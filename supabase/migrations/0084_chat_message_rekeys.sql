-- Восстановление личной переписки после смены ключа.
--
-- Кто переустановил приложение до появления копий ключей (0083), получил
-- новый ключ, и вся прежняя личная переписка у него не расшифровывается. Но
-- его собеседник её прочитать может: общий секрет пары строится из ключа
-- собеседника и старого публичного ключа, а старый публичный ключ телефон
-- собеседника запомнил (закреплённый ключ).
--
-- Поэтому телефон собеседника, заметив смену ключа, расшифровывает вашу общую
-- историю и кладёт сюда копии, зашифрованные под новый ключ. Сами сообщения не
-- меняются. Видит копию только тот, для кого она сделана.

create table chat_message_rekeys (
  message_id     uuid not null references chat_messages on delete cascade,
  -- Новый публичный ключ получателя, под который сделана копия: если он
  -- сменится ещё раз, старые копии просто перестанут подходить.
  recipient_key  text not null check (char_length(recipient_key) between 40 and 64),
  recipient_id   uuid not null references profiles on delete cascade,
  helper_id      uuid not null references profiles on delete cascade,
  ciphertext     text not null check (length(ciphertext) <= 65536),
  nonce          text not null check (length(nonce) <= 64),
  mac            text not null check (length(mac) <= 64),
  signature      text not null check (length(signature) <= 256),
  created_at     timestamptz not null default now(),
  primary key (message_id, recipient_key)
);

create index chat_message_rekeys_recipient_idx on chat_message_rekeys (recipient_id, message_id);

alter table chat_message_rekeys enable row level security;

revoke all on chat_message_rekeys from anon, authenticated;
grant select, insert on chat_message_rekeys to authenticated;

create policy "копии: вижу сделанные для меня" on chat_message_rekeys
  for select to authenticated using (recipient_id = auth.uid());

-- Класть может только второй участник того же личного чата и только для
-- первого: сообщение из их общего личного чата, оба в нём состоят.
create policy "копии: кладёт собеседник по личному чату" on chat_message_rekeys
  for insert to authenticated with check (
    helper_id = auth.uid()
    and recipient_id <> auth.uid()
    and exists (
      select 1
      from chat_messages m
      join chat_conversations c on c.id = m.conversation_id and c.direct_key is not null
      join chat_members me on me.conversation_id = c.id and me.profile_id = auth.uid()
      join chat_members them on them.conversation_id = c.id and them.profile_id = recipient_id
      where m.id = message_id
    )
  );
