-- Системный профиль «ChaWo»: владелец системных каналов @chawo_*.
-- Раньше владельцем был профиль Алексея, и в приложении он видел все каналы
-- «уже подписанным» — функцию подписки нельзя было ни показать, ни проверить.
-- Профиль без пароля и входа (синтетический адрес, как у VK/Яндекс-аккаунтов).
-- Повторный запуск безопасен.

do $$
declare
  sys constant uuid := '00000000-0000-4000-8000-0000000c4a77';
  alexey constant uuid := '71b20b93-1d0f-4671-af42-576809d176f9';
  chans uuid[];
begin
  if not exists (select 1 from auth.users where id = sys) then
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
    values (sys, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'system.chawo@id.socialworld.internal', now(), now(), now(),
            '{"display_name": "ChaWo", "oauth_provider": "system"}'::jsonb);
  end if;

  update profiles set display_name = 'ChaWo', city = null, bio = 'Официальные каналы ChaWo'
  where id = sys;

  select array_agg(id) into chans from chat_conversations where is_channel and handle like 'chawo\_%';

  -- Владелец, автор постов и «создатель» — системный профиль.
  update chat_conversations set created_by = sys where id = any (chans);
  update chat_messages set sender_id = sys where conversation_id = any (chans) and sender_id = alexey;

  insert into chat_members (conversation_id, profile_id, role)
  select id, sys, 'owner' from unnest(chans) id
  on conflict (conversation_id, profile_id) do update set role = 'owner';

  -- Алексей — обычный подписчик: убираем его как владельца, дальше подписка
  -- идёт теми же кнопками, что у всех.
  delete from chat_members where conversation_id = any (chans) and profile_id = alexey;
  delete from chat_notification_prefs where conversation_id = any (chans) and profile_id = alexey;
end $$;

select c.handle, m.profile_id = '00000000-0000-4000-8000-0000000c4a77' as system_owner,
       (select count(*) from chat_members x where x.conversation_id = c.id) as members
from chat_conversations c join chat_members m on m.conversation_id = c.id and m.role = 'owner'
where c.is_channel order by c.handle;
