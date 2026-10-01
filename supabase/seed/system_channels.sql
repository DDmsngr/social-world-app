-- Системные каналы ChaWo, которые наполняет tools/channel-feeder.
-- Разовый скрипт (не миграция): владелец — конкретный профиль Алексея.
-- Повторный запуск ничего не ломает: существующие @handle пропускаются.

with owner as (
  select id from profiles where id = '71b20b93-1d0f-4671-af42-576809d176f9'
), seed (handle, title, topic, description) as (values
  ('chawo_memes',   'Мемы',                 'memes',   'Смешное каждый час. Отбор, без рекламы и повторов.'),
  ('chawo_news',    'Новости',              'news',    'Главное за день коротко: ТАСС, РБК.'),
  ('chawo_science', 'Наука и технологии',   'science', 'Открытия, гаджеты, IT: N+1, Хабр, Rozetked.'),
  ('chawo_fashion', 'Мода и красота',       'fashion', 'Тренды, образы и бьюти-новости.'),
  ('chawo_food',    'Еда',                  'food',    'Рецепты и гастрономия.'),
  ('chawo_sochi',   'Сочи сегодня',         'city',    'Что происходит в городе: новости, дороги, погода, события.'),
  ('chawo_travel',  'Путешествия',          'travel',  'Куда поехать, дешёвые билеты, лайфхаки.'),
  ('chawo_kino',    'Кино и сериалы',       'movies',  'Премьеры, трейлеры, что посмотреть вечером.'),
  ('chawo_sport',   'Спорт',                'sport',   'Результаты, трансферы, главные матчи.')
), created as (
  insert into chat_conversations (title, created_by, is_channel, description, handle, visibility, topic, invite_token)
  select s.title, o.id, true, s.description, s.handle, 'public', s.topic, replace(gen_random_uuid()::text, '-', '')
  from seed s cross join owner o
  where not exists (select 1 from chat_conversations c where c.handle = s.handle)
  returning id, created_by
)
insert into chat_members (conversation_id, profile_id, role)
select id, created_by, 'owner' from created;

select handle, title from chat_conversations where is_channel order by handle;
