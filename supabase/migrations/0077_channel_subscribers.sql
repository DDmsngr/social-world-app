-- Список подписчиков канала для его администраторов: кто подписан и с какого
-- времени. Владелец первым, дальше по порядку подписки.

create function channel_subscribers(in_channel uuid, in_limit integer default 300, in_offset integer default 0)
returns table (profile_id uuid, display_name text, avatar_url text, role text, joined_at timestamptz)
language sql stable security definer set search_path = public set row_security = off as $$
  select m.profile_id, coalesce(p.display_name, 'Без имени'), p.avatar_url, m.role, m.joined_at
  from chat_members m
  join profiles p on p.id = m.profile_id
  where m.conversation_id = in_channel
    and is_channel_admin(in_channel)
  order by (m.role = 'owner') desc, m.joined_at
  limit least(greatest(coalesce(in_limit, 300), 1), 500)
  offset greatest(coalesce(in_offset, 0), 0);
$$;

revoke all on function channel_subscribers(uuid, integer, integer) from public, anon;
grant execute on function channel_subscribers(uuid, integer, integer) to authenticated;
