-- Аудит №4: приватные broadcast-каналы. Накатывать от supabase_admin:
-- realtime.messages принадлежит supabase_realtime_admin, у postgres нет прав
-- ставить на неё политики. Функция доступа — в 0067.
--
-- Приложение с этой версии подключается к call:<id> и typing:<id> с
-- private: true, и Realtime проверяет эти политики при входе в канал и на
-- каждое отправленное сообщение. Старые сборки ходят в открытые каналы с тем
-- же именем — это другой канал, они с новыми не пересекаются. Когда все
-- обновятся, открытые каналы выключаются флагом private_only у тенанта.

create policy chawo_broadcast_receive
  on realtime.messages for select to authenticated
  using (public.realtime_topic_allowed(realtime.topic()));

create policy chawo_broadcast_send
  on realtime.messages for insert to authenticated
  with check (public.realtime_topic_allowed(realtime.topic()));
