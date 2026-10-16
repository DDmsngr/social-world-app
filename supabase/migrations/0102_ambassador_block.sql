-- Блок «От амбассадора» в ленте города (ТЗ, преимущество 7): кто амбассадор
-- города и его ближайшие события и квесты. Одна маленькая выборка по
-- индексам — снимок не нужен.

create function ambassador_city_block(in_city text) returns jsonb
language sql stable security definer set search_path = public as $$
  with a as (
    select a.profile_id, a.role, p.display_name, p.username, p.avatar_url
    from ambassadors a join profiles p on p.id = a.profile_id and p.status <> 'blocked'
    where a.city = in_city and a.ended_at is null
      and not is_hidden_between(auth.uid(), a.profile_id)
  ), items as (
    select 'event' as kind, e.id, e.title, e.starts_at
    from events e, a
    where e.author_id = a.profile_id and e.status = 'active'
      and coalesce(e.ends_at, e.starts_at + interval '3 hours') > now()
    union all
    select 'quest', q.id, q.title, q.starts_at
    from quests q, a
    where q.author_id = a.profile_id and q.status = 'active' and q.moderation = 'active'
      and (q.ends_at is null or q.ends_at > now())
  )
  -- Нет амбассадора в городе — null, и блок в ленте не показывается.
  select (
    select jsonb_build_object(
      'profile_id', a.profile_id, 'role', a.role, 'name', coalesce(a.display_name, a.username),
      'username', a.username, 'avatar_url', a.avatar_url,
      'items', coalesce((select jsonb_agg(jsonb_build_object('kind', i.kind, 'id', i.id, 'title', i.title,
                                                             'starts_at', i.starts_at) order by i.starts_at)
                         from (select * from items order by starts_at limit 6) i), '[]'::jsonb))
    from a
  )
$$;

revoke all on function ambassador_city_block(text) from public, anon, authenticated;
grant execute on function ambassador_city_block(text) to authenticated;
