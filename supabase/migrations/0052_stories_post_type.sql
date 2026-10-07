-- 0052: лента сторис отдаёт тип исходного поста (статья, маршрут, обычный пост),
-- чтобы на плитке было видно «статья», а в просмотре была кнопка «Читать
-- статью». Тип берётся из самого поста, отдельно не хранится.

drop function stories_feed();

create function stories_feed()
returns table (
  id            uuid,
  author_id     uuid,
  author_name   text,
  author_avatar text,
  kind          text,
  media_url     text,
  body          text,
  bg            smallint,
  duration_sec  smallint,
  post_id       uuid,
  created_at    timestamptz,
  expires_at    timestamptz,
  viewed        boolean,
  view_count    bigint,
  followed      boolean,
  post_type     text
)
language sql stable security definer set search_path = public as $$
  select
    s.id, s.author_id, pr.display_name, pr.avatar_url,
    s.kind, s.media_url, s.body, s.bg, s.duration_sec, s.post_id,
    s.created_at, s.expires_at,
    exists (select 1 from story_views v where v.story_id = s.id and v.viewer_id = auth.uid()),
    case when s.author_id = auth.uid()
         then (select count(*) from story_views v where v.story_id = s.id) end,
    exists (
      select 1 from follows f
      where f.follower_id = auth.uid() and f.target_type = 'profile' and f.target_id = s.author_id
    ),
    case
      when p.id is null then null
      when p.route_id is not null then 'route'
      else p.post_type
    end
  from stories s
  join profiles pr on pr.id = s.author_id
  left join posts p on p.id = s.post_id
  where s.expires_at > now()
    and story_visible_to_me(s.author_id, s.visibility)
  order by s.created_at
  limit 300;
$$;

revoke all on function stories_feed() from public, anon;
grant execute on function stories_feed() to authenticated;
