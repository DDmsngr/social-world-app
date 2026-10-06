-- Аватар канала (и группы): колонка avatar_url была с 0039, но поставить её
-- было нечем. set_channel_avatar — владелец или админ канала; my_chats отдаёт
-- аватар канала в peer_avatar (у личных диалогов там по-прежнему аватар
-- собеседника), поэтому список чатов показывает его без новых полей.

create function set_channel_avatar(in_channel uuid, in_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if in_url is not null and (char_length(in_url) > 500 or in_url !~ '^https://') then
    raise exception 'некорректная ссылка';
  end if;
  if not exists (
    select 1 from chat_members m
    join chat_conversations c on c.id = m.conversation_id
    where m.conversation_id = in_channel
      and m.profile_id = auth.uid()
      and m.role in ('owner', 'admin')
      and c.direct_key is null
  ) then
    raise exception 'менять аватар может только владелец или админ';
  end if;
  update chat_conversations set avatar_url = in_url where id = in_channel;
end;
$$;

revoke all on function set_channel_avatar(uuid, text) from public, anon;
grant execute on function set_channel_avatar(uuid, text) to authenticated;

-- my_chats: тело из базы без изменений, кроме peer_avatar.
CREATE OR REPLACE FUNCTION public.my_chats(in_conversation uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, kind text, title text, member_count integer, my_role text, closed boolean, peer_id uuid, peer_name text, peer_avatar text, peer_last_read_at timestamp with time zone, last_id uuid, last_kind text, last_sender_id uuid, last_sender_name text, last_sent_at timestamp with time zone, last_body text, last_ciphertext text, last_nonce text, last_mac text, last_signature text, unread_count integer, last_read boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET row_security TO 'off'
AS $function$
  select c.id,
         case when c.is_channel then 'channel'
              when c.direct_key is not null then 'direct'
              when c.quest_id is not null then 'quest'
              else 'group' end,
         coalesce(c.title, q.title),
         (select count(*)::int from chat_members m2 where m2.conversation_id = c.id),
         me.role,
         c.closed_at is not null,
         peer.profile_id, pp.display_name, coalesce(pp.avatar_url, c.avatar_url), peer.last_read_at,
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
$function$;
