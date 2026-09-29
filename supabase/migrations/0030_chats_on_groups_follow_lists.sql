-- Переписка включается (решение Алексея 29.09 — обратная к 0014), плюс
-- групповые чаты и списки подписчиков/подписок.
--
-- Личные диалоги остаются со сквозным шифрованием (шифротекст, как в 0003).
-- Группы и квест-чаты — БЕЗ E2EE: текст лежит в `body`, доступ режут RLS и
-- членство. Смешать нельзя: политика вставки пускает открытый текст только
-- в недиалоговые чаты, а шифротекст — только в личные.

-- ── 1. Снять блокировку 0014 ────────────────────────────────────────────────

grant execute on function create_direct_conversation(uuid) to authenticated;
grant insert on chat_messages to authenticated;
grant insert, update on chat_public_keys to authenticated;

-- Личный диалог не создаётся с тем, кто заблокировал меня (или кого я).
create or replace function create_direct_conversation(in_peer uuid)
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
  if exists (
    select 1 from user_blocks b
    where b.kind = 'block'
      and ((b.blocker_id = current_profile and b.blocked_id = in_peer)
        or (b.blocker_id = in_peer and b.blocked_id = current_profile))
  ) then
    raise exception 'chat_blocked: переписка недоступна';
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

-- ── 2. Схема групп ──────────────────────────────────────────────────────────

alter table chat_conversations
  add column title      text check (title is null or char_length(trim(title)) between 1 and 80),
  add column created_by uuid references profiles on delete set null;

alter table chat_members
  add column role text not null default 'member' check (role in ('owner', 'member'));

-- Сообщение — либо шифротекст (личный диалог), либо открытый текст (группа).
alter table chat_messages
  add column body text check (body is null or char_length(body) between 1 and 4000),
  alter column ciphertext drop not null,
  alter column nonce drop not null,
  alter column mac drop not null,
  alter column signature drop not null,
  add constraint chat_messages_payload_check check (
    (body is not null and ciphertext is null and nonce is null and mac is null and signature is null)
    or
    (body is null and ciphertext is not null and nonce is not null and mac is not null and signature is not null)
  );

-- Время отправки ставит сервер: от него зависят порядок и счётчик
-- непрочитанного, клиентскому значению тут доверять нельзя.
create function chat_messages_server_time() returns trigger
language plpgsql as $$
begin
  new.sent_at := now();
  return new;
end;
$$;

create trigger chat_messages_server_time before insert on chat_messages
  for each row execute function chat_messages_server_time();

-- Антиспам: не больше 60 сообщений в минуту от одного человека.
create function chat_messages_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from chat_messages
       where sender_id = new.sender_id and sent_at > now() - interval '1 minute') >= 60 then
    raise exception 'rate_limit: слишком часто, попробуйте позже'
      using errcode = 'P0001', hint = 'chat_messages';
  end if;
  return new;
end;
$$;

create trigger chat_messages_rate_limit before insert on chat_messages
  for each row execute function chat_messages_rate_limit();

create trigger chat_conversations_rate_limit before insert on chat_conversations
  for each row execute function enforce_rate_limit('created_by', '3600', '10');

-- Можно ли писать в чат и в каком виде. Заменяет chat_messages_open_only
-- из 0023: закрытый чат по-прежнему не принимает сообщений.
create function chat_can_post(in_conversation uuid, in_plain boolean)
returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select c.closed_at is null
     and case
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

revoke all on function chat_can_post from public;
grant execute on function chat_can_post to authenticated;

drop policy chat_messages_open_only on chat_messages;

create policy chat_messages_can_post
  on chat_messages as restrictive for insert to authenticated
  with check (coalesce(chat_can_post(conversation_id, body is not null), false));

-- ── 3. Функции групп ────────────────────────────────────────────────────────

create function chat_is_blocked_pair(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_blocks x
    where x.kind = 'block'
      and ((x.blocker_id = a and x.blocked_id = b) or (x.blocker_id = b and x.blocked_id = a))
  );
$$;

revoke all on function chat_is_blocked_pair from public;

create function create_group_chat(in_title text, in_members uuid[])
returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  conv uuid;
begin
  if me is null then raise exception 'authentication required'; end if;
  if in_title is null or char_length(trim(in_title)) = 0 then
    raise exception 'title required';
  end if;
  if coalesce(array_length(in_members, 1), 0) > 199 then
    raise exception 'too many members';
  end if;

  insert into chat_conversations (title, created_by)
  values (trim(in_title), me)
  returning id into conv;

  insert into chat_members (conversation_id, profile_id, role)
  values (conv, me, 'owner');

  insert into chat_members (conversation_id, profile_id)
  select conv, p.id
  from profiles p
  where p.id = any (in_members)
    and p.id <> me
    and p.status = 'active'
    and not chat_is_blocked_pair(me, p.id)
  on conflict do nothing;

  return conv;
end;
$$;

-- Добавлять может любой участник группы (как в DDChat): закрытых групп с
-- модерацией входа пока нет.
create function add_chat_members(in_conversation uuid, in_members uuid[])
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare me uuid := auth.uid();
begin
  if not exists (
    select 1 from chat_members m
    join chat_conversations c on c.id = m.conversation_id
    where m.conversation_id = in_conversation and m.profile_id = me
      and c.direct_key is null and c.quest_id is null and c.closed_at is null
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

-- Убрать себя (выйти) может каждый, другого — только владелец. Если выходит
-- владелец, группа переходит к самому давнему участнику; ушёл последний —
-- группа удаляется вместе с перепиской.
create function remove_chat_member(in_conversation uuid, in_profile uuid)
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  me uuid := auth.uid();
  my_role text;
  was_owner boolean;
begin
  select m.role into my_role
  from chat_members m
  join chat_conversations c on c.id = m.conversation_id
  where m.conversation_id = in_conversation and m.profile_id = me
    and c.direct_key is null and c.quest_id is null;
  if my_role is null then raise exception 'not allowed'; end if;
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

create function rename_group_chat(in_conversation uuid, in_title text)
returns void
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  if not exists (
    select 1 from chat_members m
    join chat_conversations c on c.id = m.conversation_id
    where m.conversation_id = in_conversation and m.profile_id = auth.uid()
      and m.role = 'owner' and c.direct_key is null and c.quest_id is null
  ) then
    raise exception 'not allowed';
  end if;
  update chat_conversations set title = trim(in_title) where id = in_conversation;
end;
$$;

-- Список чатов одним запросом: последнее сообщение и счётчик непрочитанного
-- считаются на сервере, а не выкачиванием всей истории каждого диалога.
-- Пустые личные диалоги (открыли «Написать», но ничего не отправили) в списке
-- не показываются. С in_conversation — карточка одного чата (для экрана
-- переписки), пустой личный диалог при этом отдаётся.
create function my_chats(in_conversation uuid default null)
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
  last_sender_id    uuid,
  last_sender_name  text,
  last_sent_at      timestamptz,
  last_body         text,
  last_ciphertext   text,
  last_nonce        text,
  last_mac          text,
  last_signature    text,
  unread_count      integer
)
language sql stable security definer set search_path = public set row_security = off as $$
  select c.id,
         case when c.direct_key is not null then 'direct'
              when c.quest_id is not null then 'quest'
              else 'group' end,
         coalesce(c.title, q.title),
         (select count(*)::int from chat_members m2 where m2.conversation_id = c.id),
         me.role,
         c.closed_at is not null,
         peer.profile_id, pp.display_name, pp.avatar_url, peer.last_read_at,
         lm.id, lm.sender_id, sp.display_name, lm.sent_at,
         lm.body, lm.ciphertext, lm.nonce, lm.mac, lm.signature,
         (select count(*)::int from chat_messages x
           where x.conversation_id = c.id and x.sender_id <> me.profile_id
             and (me.last_read_at is null or x.sent_at > me.last_read_at))
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
    where x.conversation_id = c.id
    order by x.sent_at desc limit 1
  ) lm on true
  left join profiles sp on sp.id = lm.sender_id
  where me.profile_id = auth.uid()
    and (in_conversation is null or c.id = in_conversation)
    and (in_conversation is not null or not (c.direct_key is not null and lm.id is null))
  order by coalesce(lm.sent_at, c.created_at) desc;
$$;

revoke all on function create_group_chat, add_chat_members, remove_chat_member,
  rename_group_chat, my_chats from public;
grant execute on function create_group_chat, add_chat_members, remove_chat_member,
  rename_group_chat, my_chats to authenticated;

-- ── 4. Подписчики и подписки ────────────────────────────────────────────────
-- follows по RLS видны только их автору, поэтому списки — через функции.
-- Заблокированные и скрытые пары в списки не попадают.

create function profile_followers(in_profile uuid, in_limit integer default 50, in_offset integer default 0)
returns table (id uuid, display_name text, avatar_url text, followed_by_me boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url,
         exists (select 1 from follows f2
                  where f2.follower_id = auth.uid()
                    and f2.target_type = 'profile' and f2.target_id = p.id)
  from follows f
  join profiles p on p.id = f.follower_id
  where f.target_type = 'profile' and f.target_id = in_profile
    and p.status <> 'blocked'
    and not is_hidden_between(auth.uid(), p.id)
    and not is_hidden_between(auth.uid(), in_profile)
  order by f.created_at desc
  limit least(in_limit, 100) offset greatest(in_offset, 0);
$$;

create function profile_following(in_profile uuid, in_limit integer default 50, in_offset integer default 0)
returns table (id uuid, display_name text, avatar_url text, followed_by_me boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url,
         exists (select 1 from follows f2
                  where f2.follower_id = auth.uid()
                    and f2.target_type = 'profile' and f2.target_id = p.id)
  from follows f
  join profiles p on p.id = f.target_id
  where f.follower_id = in_profile and f.target_type = 'profile'
    and p.status <> 'blocked'
    and not is_hidden_between(auth.uid(), p.id)
    and not is_hidden_between(auth.uid(), in_profile)
  order by f.created_at desc
  limit least(in_limit, 100) offset greatest(in_offset, 0);
$$;

revoke all on function profile_followers, profile_following from public;
grant execute on function profile_followers, profile_following to authenticated;
