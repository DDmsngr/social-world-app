-- 0074: длинное видео в историях режется на части по 30 секунд.
--
-- Видео момента на 50 секунд раньше обрезалось на тридцатой секунде. Теперь
-- клиент публикует несколько историй подряд с одним и тем же роликом, а у каждой
-- есть смещение start_sec: с какой секунды ролика она начинается. Просмотр
-- перематывает видео на это место и играет не больше 30 секунд.
-- Старые клиенты не передают смещение (0) и получают лишнюю колонку в ленте.

alter table stories
  add column if not exists start_sec smallint not null default 0
  check (start_sec between 0 and 3600);

-- ── создание ────────────────────────────────────────────────────────────────

drop function create_story(text, text, text, integer, integer, text, uuid);

create function create_story(
  in_kind       text,
  in_media_url  text,
  in_body       text,
  in_bg         integer,
  in_duration   integer,
  in_visibility text,
  in_post       uuid,
  in_start      integer default 0
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  sid uuid;
begin
  if me is null then
    raise exception 'Нужна авторизация' using errcode = '28000';
  end if;
  if in_post is not null and not exists (
    select 1 from posts where id = in_post and author_id = me
  ) then
    raise exception 'Сторис можно сделать только из своего поста' using errcode = '42501';
  end if;

  -- Старые истории не копим: свои, истёкшие больше недели назад, чистим.
  delete from stories where author_id = me and expires_at < now() - interval '7 days';

  insert into stories (author_id, kind, media_url, body, bg, duration_sec, visibility, post_id, start_sec)
  values (
    me, in_kind, in_media_url, nullif(btrim(in_body), ''),
    coalesce(in_bg, 0), coalesce(in_duration, 5), coalesce(in_visibility, 'public'), in_post,
    least(greatest(coalesce(in_start, 0), 0), 3600)
  )
  returning id into sid;
  return sid;
end;
$$;

revoke all on function create_story(text, text, text, integer, integer, text, uuid, integer) from public, anon;
grant execute on function create_story(text, text, text, integer, integer, text, uuid, integer) to authenticated;

-- ── лента сторис ────────────────────────────────────────────────────────────

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
  post_type     text,
  start_sec     smallint
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
    end,
    s.start_sec
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
