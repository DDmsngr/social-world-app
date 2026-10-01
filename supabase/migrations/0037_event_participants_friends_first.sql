-- «Кто идёт»: сначала те, с кем у меня связь. Ранг: взаимная подписка выше
-- односторонней, дальше по времени записи. В ленте событий у каждого события
-- приходит превью из четырёх человек в том же порядке (мини-аватарки в углу
-- карточки).

create function friend_rank(a uuid, b uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (exists (select 1 from follows
                  where follower_id = a and target_type = 'profile' and target_id = b))::int
       + (exists (select 1 from follows
                  where follower_id = b and target_type = 'profile' and target_id = a))::int;
$$;

revoke all on function friend_rank(uuid, uuid) from public, anon, authenticated;

drop function city_events(integer, uuid);

create function city_events(
  in_limit integer default 50,
  in_event uuid default null
)
returns table (
  id                   uuid,
  author_id            uuid,
  author_name          text,
  avatar_url           text,
  title                text,
  description          text,
  starts_at            timestamptz,
  ends_at              timestamptz,
  place_title          text,
  cover_url            text,
  created_at           timestamptz,
  participant_count    bigint,
  joined_by_me         boolean,
  place_id             uuid,
  place_latitude       double precision,
  place_longitude      double precision,
  route_points         jsonb,
  participants_preview jsonb
)
language sql stable security definer set search_path = public as $$
  select e.id,
         e.author_id,
         pr.display_name,
         pr.avatar_url,
         e.title,
         e.description,
         e.starts_at,
         e.ends_at,
         pl.title,
         e.cover_url,
         e.created_at,
         count(ep.profile_id),
         coalesce(bool_or(ep.profile_id = auth.uid()), false),
         pl.id,
         st_y(pl.geo::geometry),
         st_x(pl.geo::geometry),
         e.route_points,
         (
           select coalesce(jsonb_agg(jsonb_build_object(
                    'id', x.profile_id, 'name', x.display_name,
                    'avatar_url', x.avatar_url, 'friend', x.fr > 0
                  ) order by x.fr desc, x.joined_at), '[]'::jsonb)
           from (
             select ep2.profile_id, p2.display_name, p2.avatar_url, ep2.joined_at,
                    friend_rank(auth.uid(), ep2.profile_id) as fr
             from event_participants ep2
             join profiles p2 on p2.id = ep2.profile_id
             where ep2.event_id = e.id
               and p2.status <> 'blocked'
               and not is_hidden_between(auth.uid(), ep2.profile_id)
             order by friend_rank(auth.uid(), ep2.profile_id) desc, ep2.joined_at
             limit 4
           ) x
         )
  from events e
  join profiles pr on pr.id = e.author_id
  left join places pl on pl.id = e.place_id
  left join event_participants ep on ep.event_id = e.id
  where e.status = 'active'
    and (in_event is null or e.id = in_event)
    and pr.status <> 'blocked'
    and not is_hidden_between(auth.uid(), e.author_id)
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and (
          (r.target = 'event' and r.target_id = e.id) or
          (r.target = 'profile' and r.target_id = e.author_id)
        )
    )
  group by e.id, pr.id, pl.id
  order by e.starts_at asc
  limit least(in_limit, 100);
$$;

revoke all on function city_events(integer, uuid) from public, anon;
grant execute on function city_events(integer, uuid) to authenticated;

drop function event_participants_list(uuid, integer);

create function event_participants_list(in_event uuid, in_limit integer default 100)
returns table (
  profile_id uuid, display_name text, avatar_url text,
  joined_at timestamptz, is_friend boolean
)
language sql stable security definer set search_path = public as $$
  select ep.profile_id, p.display_name, p.avatar_url, ep.joined_at,
         friend_rank(auth.uid(), ep.profile_id) > 0
  from event_participants ep
  join profiles p on p.id = ep.profile_id
  where ep.event_id = in_event
    and p.status <> 'blocked'
    and not is_hidden_between(auth.uid(), ep.profile_id)
  order by friend_rank(auth.uid(), ep.profile_id) desc, ep.joined_at
  limit least(in_limit, 200);
$$;

revoke all on function event_participants_list(uuid, integer) from public, anon;
grant execute on function event_participants_list(uuid, integer) to authenticated;
