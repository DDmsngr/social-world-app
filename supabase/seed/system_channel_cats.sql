-- Системный канал «Котики» (14.10.2026): его наполняет tools/channel-feeder
-- (handle chawo_cats, источники — в feed.mjs). Разовый скрипт, не миграция;
-- запускать после system_channels.sql: владелец — системный профиль «ChaWo».
-- Повторный запуск ничего не ломает: существующий @handle пропускается.
-- Тема из готового списка каталога — other, а «котики» и «животные» — свои
-- темы (миграция 0075), по ним канал находят в каталоге.
-- Аватарка лежит в публичном бакете avatars: system/chawo_cats.png
-- (рисуется tools/channel-feeder/make_cats_avatar.py).

with owner as (
  select id from profiles where id = '00000000-0000-4000-8000-0000000c4a77'
), created as (
  insert into chat_conversations (title, created_by, is_channel, description, handle, visibility, topic, topics, avatar_url, invite_token)
  select 'Котики', o.id, true,
         'Котики на полставки: мурчим, падаем с полок и делаем вид, что так и задумано. Свежая порция каждые полчаса.',
         'chawo_cats', 'public', 'other', array['котики', 'животные'],
         'https://api-socialworld.deepdrift.tech/storage/v1/object/public/avatars/system/chawo_cats.png',
         replace(gen_random_uuid()::text, '-', '')
  from owner o
  where not exists (select 1 from chat_conversations c where c.handle = 'chawo_cats')
  returning id, created_by
)
insert into chat_members (conversation_id, profile_id, role)
select id, created_by, 'owner' from created;

select handle, title, topics, avatar_url from chat_conversations where handle = 'chawo_cats';
