-- 0075: у канала несколько тем (свои в том числе) и посты наполнителя с их
-- настоящим временем.
--
-- 1. Тем у канала до пяти: готовые из каталога (news, food…) и свои словами
--    («настолки», «кофе в Сочи»). Колонка topic остаётся: это главная готовая
--    тема для старых версий приложения, их check не трогаем.
-- 2. channel_feed_post принимает время публикации. Раньше все посты ложились
--    «сейчас», а наполнитель на GitHub просыпается раз в несколько часов и
--    выкладывал накопившееся пачкой. Теперь у поста время источника, и лента
--    канала идёт ровно по времени, даже если пост доехал позже.

alter table chat_conversations
  add column if not exists topics text[] not null default '{}';

alter table chat_conversations
  drop constraint if exists chat_conversations_topics_count;
alter table chat_conversations
  add constraint chat_conversations_topics_count check (cardinality(topics) <= 5);

update chat_conversations
   set topics = array[topic]
 where is_channel and topic is not null and topics = '{}';

create index if not exists chat_conversations_topics_idx
  on chat_conversations using gin (topics) where is_channel;

-- Тему чистим: пробелы схлопнуть, 2–24 знака, без повторов (без учёта
-- регистра), не больше пяти. Готовые темы приходят как есть (латиницей).
create or replace function clean_channel_topics(in_topics text[]) returns text[]
language sql immutable as $$
  select coalesce((array_agg(t order by ord))[1:5], '{}')
  from (
    select distinct on (lower(t)) t, ord
    from (
      select regexp_replace(btrim(x), '\s+', ' ', 'g') as t, ord
      from unnest(coalesce(in_topics, '{}')) with ordinality as u(x, ord)
    ) a
    where char_length(t) between 2 and 24
    order by lower(t), ord
  ) b;
$$;

-- Главная готовая тема: первая из списка, что есть в каталоге, иначе other.
create or replace function primary_channel_topic(in_topics text[]) returns text
language sql immutable as $$
  select coalesce(
    (select t from unnest(coalesce(in_topics, '{}')) with ordinality as u(t, ord)
      where t in ('news','science','fashion','food','memes','city','travel','movies','sport')
      order by ord limit 1),
    'other');
$$;

-- ── создание и правка ───────────────────────────────────────────────────────

drop function create_channel(text, text, text, text, text);

create function create_channel(
  in_title text, in_description text, in_visibility text,
  in_handle text default null, in_topic text default 'other',
  in_topics text[] default null
) returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid;
  h text := nullif(lower(trim(coalesce(in_handle, ''))), '');
  list text[] := clean_channel_topics(coalesce(in_topics, array[coalesce(in_topic, 'other')]));
begin
  if me is null then raise exception 'authentication required'; end if;
  if in_title is null or char_length(trim(in_title)) = 0 then raise exception 'нужно название'; end if;
  if in_visibility not in ('public', 'private') then raise exception 'неизвестный тип канала'; end if;
  if in_visibility = 'public' and h is null then raise exception 'у публичного канала нужен адрес'; end if;
  if in_visibility = 'private' then h := null; end if;
  if h is not null and exists (select 1 from chat_conversations where handle = h) then
    raise exception 'адрес @% уже занят', h;
  end if;

  insert into chat_conversations (
    title, created_by, is_channel, description, handle, visibility, topic, topics, invite_token
  ) values (
    trim(in_title), me, true, nullif(trim(coalesce(in_description, '')), ''), h,
    in_visibility, primary_channel_topic(list), list, replace(gen_random_uuid()::text, '-', '')
  ) returning id into conv;

  insert into chat_members (conversation_id, profile_id, role) values (conv, me, 'owner');
  return conv;
end;
$$;

drop function update_channel(uuid, text, text, text, text, text, boolean);

create function update_channel(
  in_channel uuid, in_title text, in_description text, in_visibility text,
  in_handle text, in_topic text, in_show_subscribers boolean,
  in_topics text[] default null
) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  h text := nullif(lower(trim(coalesce(in_handle, ''))), '');
  list text[] := case when in_topics is null then null else clean_channel_topics(in_topics) end;
begin
  if coalesce(channel_role(in_channel), '') <> 'owner' then raise exception 'not allowed'; end if;
  if in_visibility not in ('public', 'private') then raise exception 'неизвестный тип канала'; end if;
  if in_visibility = 'public' and h is null then raise exception 'у публичного канала нужен адрес'; end if;
  if in_visibility = 'private' then h := null; end if;
  if h is not null and exists (select 1 from chat_conversations where handle = h and id <> in_channel) then
    raise exception 'адрес @% уже занят', h;
  end if;
  update chat_conversations
     set title = trim(in_title),
         description = nullif(trim(coalesce(in_description, '')), ''),
         visibility = in_visibility,
         handle = h,
         topic = case when list is not null then primary_channel_topic(list)
                      else coalesce(in_topic, topic) end,
         topics = case when list is not null then list
                       when in_topic is not null then array[in_topic]
                       else topics end,
         show_subscribers = coalesce(in_show_subscribers, show_subscribers)
   where id = in_channel;
end;
$$;

-- ── карточка и каталог ──────────────────────────────────────────────────────

drop function channel_info(uuid, text);

create function channel_info(in_channel uuid default null, in_handle text default null)
returns table (
  id uuid, title text, description text, handle text, visibility text, topic text,
  avatar_url text, show_subscribers boolean, subscriber_count integer,
  my_role text, requested boolean, invite_token text, pending_requests integer,
  topics text[]
)
language sql stable security definer set search_path = public set row_security = off as $$
  select c.id, c.title, c.description, c.handle, c.visibility, c.topic, c.avatar_url,
         c.show_subscribers,
         case when c.show_subscribers or is_channel_admin(c.id)
              then (select count(*)::int from chat_members m where m.conversation_id = c.id) end,
         channel_role(c.id),
         exists (select 1 from channel_join_requests r
                 where r.conversation_id = c.id and r.profile_id = auth.uid()),
         case when is_channel_admin(c.id) then c.invite_token end,
         case when is_channel_admin(c.id)
              then (select count(*)::int from channel_join_requests r where r.conversation_id = c.id) end,
         case when cardinality(c.topics) > 0 then c.topics else array[coalesce(c.topic, 'other')] end
  from chat_conversations c
  where c.is_channel
    and auth.uid() is not null
    and (c.id = in_channel or (in_channel is null and c.handle = lower(in_handle)));
$$;

drop function search_channels(text, text, integer);

create function search_channels(in_query text default null, in_topic text default null, in_limit integer default 50)
returns table (
  id uuid, title text, description text, handle text, topic text, avatar_url text,
  subscriber_count integer, joined boolean, last_post_at timestamptz,
  topics text[]
)
language sql stable security definer set search_path = public set row_security = off as $$
  select c.id, c.title, c.description, c.handle, c.topic, c.avatar_url,
         case when c.show_subscribers then s.n end,
         is_chat_member(c.id),
         (select max(x.sent_at) from chat_messages x
           where x.conversation_id = c.id and x.deleted_at is null),
         case when cardinality(c.topics) > 0 then c.topics else array[coalesce(c.topic, 'other')] end
  from chat_conversations c
  cross join lateral (
    select count(*)::int as n from chat_members m where m.conversation_id = c.id
  ) s
  where c.is_channel and c.visibility = 'public'
    and auth.uid() is not null
    and (in_topic is null or c.topic = in_topic or in_topic = any(c.topics))
    and (
      coalesce(trim(in_query), '') = ''
      or c.title ilike '%' || trim(in_query) || '%'
      or c.handle ilike '%' || ltrim(trim(in_query), '@') || '%'
      or c.description ilike '%' || trim(in_query) || '%'
      or array_to_string(c.topics, ' ') ilike '%' || trim(in_query) || '%'
    )
  order by s.n desc, c.created_at
  limit least(in_limit, 100);
$$;

-- ── наполнитель: время публикации ───────────────────────────────────────────

drop function channel_feed_post(text, text, text, text, jsonb);

create function channel_feed_post(
  in_handle text, in_source_ref text, in_kind text, in_body text, in_media jsonb,
  in_sent_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  conv uuid;
  owner_id uuid;
  new_id uuid := gen_random_uuid();
  at timestamptz := least(coalesce(in_sent_at, now()), now());
begin
  select c.id, m.profile_id into conv, owner_id
  from chat_conversations c
  join chat_members m on m.conversation_id = c.id and m.role = 'owner'
  where c.is_channel and c.handle = in_handle;
  if conv is null then raise exception 'канал @% не найден', in_handle; end if;
  if in_source_ref is not null and exists (
    select 1 from chat_messages where conversation_id = conv and source_ref = in_source_ref
  ) then
    return null;
  end if;

  insert into chat_messages (id, conversation_id, sender_id, kind, body, media, source_ref, sent_at)
  values (new_id, conv, owner_id, coalesce(in_kind, 'text'),
          nullif(left(coalesce(in_body, ''), 4000), ''), in_media, in_source_ref, at);
  -- Триггер вставки (0030) ставит серверное «сейчас» и клиентскому времени не
  -- верит. Для постов наполнителя время источника нужно, поэтому правим
  -- уже вставленную строку (на обновление такого триггера нет).
  if at < now() - interval '1 second' then
    update chat_messages set sent_at = at where id = new_id;
  end if;
  return new_id;
end;
$$;

revoke all on function
  create_channel(text, text, text, text, text, text[]),
  update_channel(uuid, text, text, text, text, text, boolean, text[]),
  channel_info(uuid, text),
  search_channels(text, text, integer),
  channel_feed_post(text, text, text, text, jsonb, timestamptz),
  clean_channel_topics(text[]),
  primary_channel_topic(text[])
from public, anon;

grant execute on function
  create_channel(text, text, text, text, text, text[]),
  update_channel(uuid, text, text, text, text, text, boolean, text[]),
  channel_info(uuid, text),
  search_channels(text, text, integer)
to authenticated;

revoke execute on function channel_feed_post(text, text, text, text, jsonb, timestamptz) from authenticated;
grant execute on function channel_feed_post(text, text, text, text, jsonb, timestamptz) to service_role;
