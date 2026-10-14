-- Копия ключей личных чатов на сервере.
--
-- Раньше закрытые ключи жили только в защищённом хранилище телефона, и после
-- переустановки приложения (или на новом телефоне) вся личная переписка
-- становилась нечитаемой. Решение 14.10.2026: хранить копию ключа на сервере,
-- как облачные чаты. Приложение при входе берёт ключ отсюда, если на телефоне
-- его нет, и кладёт сюда свой, если копии ещё нет.
--
-- Строку видит и пишет только сам владелец (RLS). Честно: сервер технически
-- может прочитать переписку, «только вы двое» больше не обещаем.

create table chat_key_backups (
  profile_id     uuid primary key references profiles on delete cascade,
  exchange_seed  text not null check (char_length(exchange_seed) between 40 and 64),
  signing_seed   text not null check (char_length(signing_seed) between 40 and 64),
  updated_at     timestamptz not null default now()
);

alter table chat_key_backups enable row level security;

revoke all on chat_key_backups from anon, authenticated;
grant select, insert, update on chat_key_backups to authenticated;

create policy "ключи: вижу свои" on chat_key_backups
  for select to authenticated using (profile_id = auth.uid());

create policy "ключи: кладу свои" on chat_key_backups
  for insert to authenticated with check (profile_id = auth.uid());

create policy "ключи: обновляю свои" on chat_key_backups
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
