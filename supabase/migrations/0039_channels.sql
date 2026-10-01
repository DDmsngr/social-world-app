-- Каналы: пишут владелец и админы, остальные читают и обсуждают в комментариях.
--
-- Канал — это chat_conversations с is_channel: подписчики лежат в chat_members,
-- посты в chat_messages (открытый текст, как в группах). Поэтому список чатов,
-- счётчики непрочитанного, вложения и пуши работают без отдельной ветки.
--   * Публичный канал (visibility = public, есть @handle) находится поиском,
--     читать его можно и без подписки.
--   * Закрытый (private) — только по ссылке-приглашению или по заявке, которую
--     одобряет админ («аккредитация»).
--   * Подписка включается с выключенными уведомлениями: только счётчик.
--   * Комментарии к постам — деревом, с лайками и сортировкой «лучшие сверху»,
--     той же формы, что post_comments_tree, чтобы клиент рисовал их тем же кодом.
--   * Посты из внешних источников пишет наполнитель (GitHub Actions) сервисным
--     ключом через channel_feed_post; source_ref не даёт запостить одно дважды.

-- ── 1. схема ────────────────────────────────────────────────────────────────

alter table chat_conversations
  add column is_channel       boolean not null default false,
  add column description      text check (description is null or char_length(description) <= 500),
  add column handle           text unique check (handle is null or handle ~ '^[a-z0-9_]{4,32}$'),
  add column visibility       text check (visibility is null or visibility in ('public', 'private')),
  add column show_subscribers boolean not null default true,
  add column invite_token     text unique,
  add column topic            text check (topic is null or topic in (
    'news', 'science', 'fashion', 'food', 'memes', 'city', 'travel', 'movies', 'sport', 'other'
  )),
  add column avatar_url       text check (avatar_url is null or char_length(avatar_url) <= 500);

alter table chat_conversations add constraint chat_channel_shape check (
  (is_channel and visibility is not null and direct_key is null and quest_id is null)
  or (not is_channel and visibility is null and handle is null and invite_token is null)
);

create index chat_conversations_channels_idx on chat_conversations (topic)
  where is_channel and visibility = 'public';

alter table chat_members drop constraint chat_members_role_check;
alter table chat_members add constraint chat_members_role_check
  check (role in ('owner', 'admin', 'member'));

-- Ключ поста во внешнем источнике (tg:channel/123): защита от повторов.
alter table chat_messages add column source_ref text
  check (source_ref is null or char_length(source_ref) <= 200);
create unique index chat_messages_source_ref_uq
  on chat_messages (conversation_id, source_ref) where source_ref is not null;

create table channel_join_requests (
  conversation_id uuid not null references chat_conversations on delete cascade,
  profile_id      uuid not null references profiles on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (conversation_id, profile_id)
);
alter table channel_join_requests enable row level security;
revoke all on channel_join_requests from public, anon, authenticated;

create table channel_comments (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references chat_messages on delete cascade,
  parent_id  uuid references channel_comments on delete cascade,
  author_id  uuid not null references profiles on delete cascade,
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index channel_comments_message_idx on channel_comments (message_id, created_at);
create index channel_comments_parent_idx on channel_comments (parent_id);
alter table channel_comments enable row level security;
revoke all on channel_comments from public, anon, authenticated;

create trigger channel_comments_rate_limit before insert on channel_comments
  for each row execute function enforce_rate_limit('author_id', '60', '20');

create table channel_comment_likes (
  comment_id uuid not null references channel_comments on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, profile_id)
);
alter table channel_comment_likes enable row level security;
revoke all on channel_comment_likes from public, anon, authenticated;

-- ── 2. права ────────────────────────────────────────────────────────────────

create function channel_role(in_channel uuid) returns text
language sql stable security definer set search_path = public set row_security = off as $$
  select m.role from chat_members m
  join chat_conversations c on c.id = m.conversation_id and c.is_channel
  where m.conversation_id = in_channel and m.profile_id = auth.uid();
$$;

create function is_channel_admin(in_channel uuid) returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select coalesce(channel_role(in_channel) in ('owner', 'admin'), false);
$$;

-- Читать канал: публичный — любой вошедший, закрытый — подписчик.
create function can_read_channel(in_channel uuid) returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select exists (
    select 1 from chat_conversations c
    where c.id = in_channel and c.is_channel
      and (c.visibility = 'public' or is_chat_member(c.id))
  );
$$;

revoke all on function channel_role(uuid), is_channel_admin(uuid), can_read_channel(uuid) from public, anon;
grant execute on function channel_role(uuid), is_channel_admin(uuid), can_read_channel(uuid) to authenticated;

-- В канал пишут только владелец и админы; остальное — как было.
create or replace function chat_can_post(in_conversation uuid, in_plain boolean)
returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select c.closed_at is null
     and case
           when c.is_channel then in_plain and is_channel_admin(c.id)
           when c.direct_key is null then in_plain
           else not in_plain and not exists (
             select 1
             from chat_members m
             join user_blocks b
               on b.kind = 'block'
              and ((b.blocker_id = auth.uid() and b.blocked_id = m.profile_id)
                or (b.blocker_id = m.profile_id and b.blocked_id = auth.uid()))
             where m.conversation_id = c.id and m.profile_id <> auth.uid()
           )
         end
  from chat_conversations c
  where c.id = in_conversation;
$$;

-- Файлы публичного канала видны и без подписки.
drop policy chat_media_read on storage.objects;
create policy chat_media_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and (
      coalesce(is_chat_member(chat_media_conversation(name)), false)
      or coalesce(can_read_channel(chat_media_conversation(name)), false)
    )
  );

-- Добавлять людей в канал руками нельзя — только подписка и заявки.
create or replace function add_chat_members(in_conversation uuid, in_members uuid[])
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare me uuid := auth.uid();
begin
  if not exists (
    select 1 from chat_members m
    join chat_conversations c on c.id = m.conversation_id
    where m.conversation_id = in_conversation and m.profile_id = me
      and c.direct_key is null and c.quest_id is null and c.closed_at is null
      and not c.is_channel
  ) then
    raise exception 'not allowed';
  end if;
  if (select count(*) from chat_members where conversation_id = in_conversation)
     + coalesce(array_length(in_members, 1), 0) > 200 then
    raise exception 'too many members';
  end if;

  insert into chat_members (conversation_id, profile_id)
  select in_conversation, p.id
  from profiles p
  where p.id = any (in_members)
    and p.status = 'active'
    and not chat_is_blocked_pair(me, p.id)
  on conflict do nothing;
end;
$$;

-- Владелец не может просто «выйти» из канала: подписчики остались бы без
-- хозяина. Удалять подписчиков могут владелец и админы.
create or replace function remove_chat_member(in_conversation uuid, in_profile uuid)
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  my_role text;
  target_role text;
  channel boolean;
  was_owner boolean;
begin
  select m.role, c.is_channel into my_role, channel
  from chat_members m
  join chat_conversations c on c.id = m.conversation_id
  where m.conversation_id = in_conversation and m.profile_id = me
    and c.direct_key is null and c.quest_id is null;
  if my_role is null then raise exception 'not allowed'; end if;

  if channel then
    select role into target_role from chat_members
    where conversation_id = in_conversation and profile_id = in_profile;
    if target_role = 'owner' then
      raise exception 'владелец не может покинуть канал';
    end if;
    if in_profile <> me and my_role not in ('owner', 'admin') then
      raise exception 'not allowed';
    end if;
    if in_profile <> me and target_role = 'admin' and my_role <> 'owner' then
      raise exception 'not allowed';
    end if;
    delete from chat_members where conversation_id = in_conversation and profile_id = in_profile;
    delete from chat_notification_prefs where conversation_id = in_conversation and profile_id = in_profile;
    return;
  end if;

  if in_profile <> me and my_role <> 'owner' then raise exception 'not allowed'; end if;

  delete from chat_members
  where conversation_id = in_conversation and profile_id = in_profile
  returning role = 'owner' into was_owner;

  if not exists (select 1 from chat_members where conversation_id = in_conversation) then
    delete from chat_conversations where id = in_conversation;
  elsif was_owner then
    update chat_members set role = 'owner'
    where conversation_id = in_conversation
      and profile_id = (
        select profile_id from chat_members
        where conversation_id = in_conversation
        order by joined_at, profile_id limit 1
      );
  end if;
end;
$$;

-- Удалять посты канала могут и админы.
create or replace function delete_chat_messages(in_ids uuid[])
returns setof uuid
language sql security definer set search_path = public as $$
  update chat_messages m
     set deleted_at = now(),
         body = null, media = null, meta = null,
         ciphertext = null, nonce = null, mac = null, signature = null
   where m.id = any(in_ids)
     and m.deleted_at is null
     and (
       m.sender_id = auth.uid()
       or exists (
         select 1
         from chat_members me
         join chat_conversations c on c.id = me.conversation_id
         where me.conversation_id = m.conversation_id
           and me.profile_id = auth.uid()
           and (me.role = 'owner' or (c.is_channel and me.role = 'admin'))
           and c.direct_key is null
       )
     )
  returning m.id;
$$;

-- ── 3. список чатов знает про каналы ────────────────────────────────────────

create or replace function my_chats(in_conversation uuid default null)
returns table (
  id                uuid,
  kind              text,
  title             text,
  member_count      integer,
  my_role           text,
  closed            boolean,
  peer_id           uuid,
  peer_name         text,
  peer_avatar       text,
  peer_last_read_at timestamptz,
  last_id           uuid,
  last_kind         text,
  last_sender_id    uuid,
  last_sender_name  text,
  last_sent_at      timestamptz,
  last_body         text,
  last_ciphertext   text,
  last_nonce        text,
  last_mac          text,
  last_signature    text,
  unread_count      integer,
  last_read         boolean
)
language sql stable security definer set search_path = public set row_security = off as $$
  select c.id,
         case when c.is_channel then 'channel'
              when c.direct_key is not null then 'direct'
              when c.quest_id is not null then 'quest'
              else 'group' end,
         coalesce(c.title, q.title),
         (select count(*)::int from chat_members m2 where m2.conversation_id = c.id),
         me.role,
         c.closed_at is not null,
         peer.profile_id, pp.display_name, pp.avatar_url, peer.last_read_at,
         lm.id, lm.kind, lm.sender_id, sp.display_name, lm.sent_at,
         lm.body, lm.ciphertext, lm.nonce, lm.mac, lm.signature,
         (select count(*)::int from chat_messages x
           where x.conversation_id = c.id and x.sender_id <> me.profile_id
             and x.deleted_at is null
             and (me.last_read_at is null or x.sent_at > me.last_read_at)),
         lm.id is not null and exists (
           select 1 from chat_members r
           where r.conversation_id = c.id
             and r.profile_id <> lm.sender_id
             and r.last_read_at >= lm.sent_at
         )
  from chat_members me
  join chat_conversations c on c.id = me.conversation_id
  left join quests q on q.id = c.quest_id
  left join lateral (
    select m.profile_id, m.last_read_at from chat_members m
    where c.direct_key is not null and m.conversation_id = c.id and m.profile_id <> me.profile_id
    limit 1
  ) peer on true
  left join profiles pp on pp.id = peer.profile_id
  left join lateral (
    select x.* from chat_messages x
    where x.conversation_id = c.id and x.deleted_at is null
    order by x.sent_at desc limit 1
  ) lm on true
  left join profiles sp on sp.id = lm.sender_id
  where me.profile_id = auth.uid()
    and (in_conversation is null or c.id = in_conversation)
    and (in_conversation is not null or not (c.direct_key is not null and lm.id is null))
  order by coalesce(lm.sent_at, c.created_at) desc;
$$;

-- ── 4. жизнь канала ─────────────────────────────────────────────────────────

create function create_channel(
  in_title text, in_description text, in_visibility text,
  in_handle text default null, in_topic text default 'other'
) returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid;
  h text := nullif(lower(trim(coalesce(in_handle, ''))), '');
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
    title, created_by, is_channel, description, handle, visibility, topic, invite_token
  ) values (
    trim(in_title), me, true, nullif(trim(coalesce(in_description, '')), ''), h,
    in_visibility, coalesce(in_topic, 'other'), replace(gen_random_uuid()::text, '-', '')
  ) returning id into conv;

  insert into chat_members (conversation_id, profile_id, role) values (conv, me, 'owner');
  return conv;
end;
$$;

create function update_channel(
  in_channel uuid, in_title text, in_description text, in_visibility text,
  in_handle text, in_topic text, in_show_subscribers boolean
) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare h text := nullif(lower(trim(coalesce(in_handle, ''))), '');
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
         topic = coalesce(in_topic, topic),
         show_subscribers = coalesce(in_show_subscribers, show_subscribers)
   where id = in_channel;
end;
$$;

create function regenerate_channel_invite(in_channel uuid) returns text
language plpgsql security definer set search_path = public set row_security = off as $$
declare token text := replace(gen_random_uuid()::text, '-', '');
begin
  if not is_channel_admin(in_channel) then raise exception 'not allowed'; end if;
  update chat_conversations set invite_token = token where id = in_channel;
  return token;
end;
$$;

-- Карточка канала. Название и описание видны и у закрытого (чтобы было что
-- показать перед заявкой); посты — нет. Число подписчиков скрывается
-- настройкой, но админы видят его всегда; ссылку-приглашение видят только они.
create function channel_info(in_channel uuid default null, in_handle text default null)
returns table (
  id uuid, title text, description text, handle text, visibility text, topic text,
  avatar_url text, show_subscribers boolean, subscriber_count integer,
  my_role text, requested boolean, invite_token text, pending_requests integer
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
              then (select count(*)::int from channel_join_requests r where r.conversation_id = c.id) end
  from chat_conversations c
  where c.is_channel
    and auth.uid() is not null
    and (c.id = in_channel or (in_channel is null and c.handle = lower(in_handle)));
$$;

-- Подписаться. Публичный — сразу; закрытый — по верному токену сразу, без
-- токена уходит заявка. Возвращает 'joined' или 'requested'.
create function channel_join(in_channel uuid, in_token text default null) returns text
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  c chat_conversations;
  owner_id uuid;
begin
  if me is null then raise exception 'authentication required'; end if;
  select * into c from chat_conversations where id = in_channel and is_channel;
  if c.id is null then raise exception 'канал не найден'; end if;
  if is_chat_member(c.id) then return 'joined'; end if;

  select profile_id into owner_id from chat_members where conversation_id = c.id and role = 'owner';
  if owner_id is not null and chat_is_blocked_pair(me, owner_id) then
    raise exception 'not allowed';
  end if;

  if c.visibility = 'public' or (in_token is not null and in_token = c.invite_token) then
    insert into chat_members (conversation_id, profile_id) values (c.id, me) on conflict do nothing;
    -- По умолчанию канал не звонит: только счётчик непрочитанного.
    insert into chat_notification_prefs (profile_id, conversation_id, mode)
    values (me, c.id, 'off') on conflict do nothing;
    delete from channel_join_requests where conversation_id = c.id and profile_id = me;
    return 'joined';
  end if;

  insert into channel_join_requests (conversation_id, profile_id)
  values (c.id, me) on conflict do nothing;
  return 'requested';
end;
$$;

create function channel_requests(in_channel uuid)
returns table (profile_id uuid, display_name text, avatar_url text, created_at timestamptz)
language sql stable security definer set search_path = public set row_security = off as $$
  select r.profile_id, coalesce(p.display_name, 'Без имени'), p.avatar_url, r.created_at
  from channel_join_requests r
  join profiles p on p.id = r.profile_id
  where r.conversation_id = in_channel and is_channel_admin(in_channel)
  order by r.created_at;
$$;

create function decide_channel_request(in_channel uuid, in_profile uuid, in_approve boolean)
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  if not is_channel_admin(in_channel) then raise exception 'not allowed'; end if;
  delete from channel_join_requests where conversation_id = in_channel and profile_id = in_profile;
  if not found then return; end if;
  if in_approve then
    insert into chat_members (conversation_id, profile_id) values (in_channel, in_profile)
    on conflict do nothing;
    insert into chat_notification_prefs (profile_id, conversation_id, mode)
    values (in_profile, in_channel, 'off') on conflict do nothing;
  end if;
end;
$$;

create function set_channel_admin(in_channel uuid, in_profile uuid, in_admin boolean)
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  if coalesce(channel_role(in_channel), '') <> 'owner' then raise exception 'not allowed'; end if;
  update chat_members
     set role = case when in_admin then 'admin' else 'member' end
   where conversation_id = in_channel and profile_id = in_profile and role <> 'owner';
end;
$$;

-- Каталог публичных каналов: по теме и поиску, крупные сверху.
create function search_channels(in_query text default null, in_topic text default null, in_limit integer default 50)
returns table (
  id uuid, title text, description text, handle text, topic text, avatar_url text,
  subscriber_count integer, joined boolean, last_post_at timestamptz
)
language sql stable security definer set search_path = public set row_security = off as $$
  select c.id, c.title, c.description, c.handle, c.topic, c.avatar_url,
         case when c.show_subscribers then s.n end,
         is_chat_member(c.id),
         (select max(x.sent_at) from chat_messages x
           where x.conversation_id = c.id and x.deleted_at is null)
  from chat_conversations c
  cross join lateral (
    select count(*)::int as n from chat_members m where m.conversation_id = c.id
  ) s
  where c.is_channel and c.visibility = 'public'
    and auth.uid() is not null
    and (in_topic is null or c.topic = in_topic)
    and (
      coalesce(trim(in_query), '') = ''
      or c.title ilike '%' || trim(in_query) || '%'
      or c.handle ilike '%' || ltrim(trim(in_query), '@') || '%'
      or c.description ilike '%' || trim(in_query) || '%'
    )
  order by s.n desc, c.created_at
  limit least(in_limit, 100);
$$;

-- Лента канала, новые сверху, страницами по in_before.
create function channel_posts(in_channel uuid, in_before timestamptz default null, in_limit integer default 30)
returns table (
  id uuid, sender_id uuid, kind text, body text, media jsonb, meta jsonb,
  sent_at timestamptz, comment_count integer
)
language sql stable security definer set search_path = public set row_security = off as $$
  select x.id, x.sender_id, x.kind, x.body, x.media, x.meta, x.sent_at,
         (select count(*)::int from channel_comments k
           where k.message_id = x.id and k.deleted_at is null)
  from chat_messages x
  where x.conversation_id = in_channel
    and can_read_channel(in_channel)
    and x.deleted_at is null
    and (in_before is null or x.sent_at < in_before)
  order by x.sent_at desc
  limit least(in_limit, 100);
$$;

-- Пост наполнителя (только service_role). Автор — владелец канала.
create function channel_feed_post(
  in_handle text, in_source_ref text, in_kind text, in_body text, in_media jsonb
) returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  conv uuid;
  owner_id uuid;
  new_id uuid := gen_random_uuid();
begin
  select c.id, m.profile_id into conv, owner_id
  from chat_conversations c
  join chat_members m on m.conversation_id = c.id and m.role = 'owner'
  where c.is_channel and c.handle = in_handle;
  if conv is null then raise exception 'канал @% не найден', in_handle; end if;
  if exists (select 1 from chat_messages where conversation_id = conv and source_ref = in_source_ref) then
    return null;
  end if;

  insert into chat_messages (id, conversation_id, sender_id, kind, body, media, source_ref)
  values (new_id, conv, owner_id, coalesce(in_kind, 'text'),
          nullif(left(coalesce(in_body, ''), 4000), ''), in_media, in_source_ref);
  return new_id;
end;
$$;

-- ── 5. комментарии ──────────────────────────────────────────────────────────

create function channel_comment_message_channel(in_message uuid) returns uuid
language sql stable security definer set search_path = public set row_security = off as $$
  select m.conversation_id from chat_messages m
  join chat_conversations c on c.id = m.conversation_id and c.is_channel
  where m.id = in_message and m.deleted_at is null;
$$;

-- Та же форма, что у post_comments_tree: клиент разбирает её одним кодом.
create function channel_comments_tree(in_message uuid, in_limit integer default 300)
returns table (
  id uuid, parent_id uuid, author_id uuid, author_name text, avatar_url text,
  body text, media_urls text[], created_at timestamptz, deleted boolean,
  depth integer, like_count bigint, liked_by_me boolean
)
language sql stable security definer set search_path = public set row_security = off as $$
  with recursive likes as (
    select l.comment_id, count(*)::double precision as n
    from channel_comment_likes l
    join channel_comments k on k.id = l.comment_id and k.message_id = in_message
    group by l.comment_id
  ), tree as (
    select c.id, c.parent_id, c.author_id, c.body, c.created_at, c.deleted_at,
           0 as depth,
           array[-coalesce(l.n, 0), -extract(epoch from c.created_at)]::double precision[] as path
    from channel_comments c
    left join likes l on l.comment_id = c.id
    where c.message_id = in_message and c.parent_id is null
    union all
    select c.id, c.parent_id, c.author_id, c.body, c.created_at, c.deleted_at,
           t.depth + 1,
           t.path || array[-coalesce(l.n, 0), -extract(epoch from c.created_at)]::double precision[]
    from channel_comments c
    join tree t on c.parent_id = t.id
    left join likes l on l.comment_id = c.id
  )
  select t.id, t.parent_id, t.author_id, pr.display_name, pr.avatar_url,
         case when t.deleted_at is null then t.body end,
         '{}'::text[],
         t.created_at, t.deleted_at is not null, t.depth,
         count(l.profile_id), coalesce(bool_or(l.profile_id = auth.uid()), false)
  from tree t
  join profiles pr on pr.id = t.author_id
  left join channel_comment_likes l on l.comment_id = t.id
  where pr.status <> 'blocked'
    and can_read_channel(channel_comment_message_channel(in_message))
  group by t.id, t.parent_id, t.author_id, pr.display_name, pr.avatar_url,
           t.body, t.created_at, t.deleted_at, t.depth, t.path
  order by t.path
  limit least(in_limit, 500);
$$;

create function channel_comment_add(in_message uuid, in_parent uuid, in_body text)
returns table (id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid := channel_comment_message_channel(in_message);
begin
  if me is null then raise exception 'authentication required'; end if;
  if conv is null or not can_read_channel(conv) then raise exception 'not allowed'; end if;
  if in_parent is not null and not exists (
    select 1 from channel_comments where channel_comments.id = in_parent and message_id = in_message
  ) then
    raise exception 'ответ не к этому посту';
  end if;
  return query
  insert into channel_comments (message_id, parent_id, author_id, body)
  values (in_message, in_parent, me, trim(in_body))
  returning channel_comments.id, channel_comments.created_at;
end;
$$;

create function channel_comment_toggle_like(in_comment uuid) returns boolean
language plpgsql security definer set search_path = public set row_security = off as $$
declare me uuid := auth.uid();
begin
  if not exists (
    select 1 from channel_comments k
    where k.id = in_comment and can_read_channel(channel_comment_message_channel(k.message_id))
  ) then
    raise exception 'not allowed';
  end if;
  delete from channel_comment_likes where comment_id = in_comment and profile_id = me;
  if found then return false; end if;
  insert into channel_comment_likes (comment_id, profile_id) values (in_comment, me);
  return true;
end;
$$;

-- Удаляет автор или админ канала. Мягко: ответы других остаются в ветке.
create function channel_comment_delete(in_comment uuid) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  update channel_comments k
     set deleted_at = now(), body = '[комментарий удалён]'
   where k.id = in_comment
     and k.deleted_at is null
     and (k.author_id = auth.uid()
          or is_channel_admin(channel_comment_message_channel(k.message_id)));
end;
$$;

revoke all on function
  create_channel(text, text, text, text, text),
  update_channel(uuid, text, text, text, text, text, boolean),
  regenerate_channel_invite(uuid),
  channel_info(uuid, text),
  channel_join(uuid, text),
  channel_requests(uuid),
  decide_channel_request(uuid, uuid, boolean),
  set_channel_admin(uuid, uuid, boolean),
  search_channels(text, text, integer),
  channel_posts(uuid, timestamptz, integer),
  channel_comment_message_channel(uuid),
  channel_comments_tree(uuid, integer),
  channel_comment_add(uuid, uuid, text),
  channel_comment_toggle_like(uuid),
  channel_comment_delete(uuid),
  channel_feed_post(text, text, text, text, jsonb)
from public, anon;

grant execute on function
  create_channel(text, text, text, text, text),
  update_channel(uuid, text, text, text, text, text, boolean),
  regenerate_channel_invite(uuid),
  channel_info(uuid, text),
  channel_join(uuid, text),
  channel_requests(uuid),
  decide_channel_request(uuid, uuid, boolean),
  set_channel_admin(uuid, uuid, boolean),
  search_channels(text, text, integer),
  channel_posts(uuid, timestamptz, integer),
  channel_comments_tree(uuid, integer),
  channel_comment_add(uuid, uuid, text),
  channel_comment_toggle_like(uuid),
  channel_comment_delete(uuid)
to authenticated;

revoke execute on function channel_feed_post(text, text, text, text, jsonb) from authenticated;
grant execute on function channel_feed_post(text, text, text, text, jsonb) to service_role;
