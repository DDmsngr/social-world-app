-- Настройки уведомлений и упоминания @ник.
--
-- Категории: messages, comments (комментарии и ответы), likes (лайки и реакции),
-- mentions, follows, events, quests, needs, points. Включены по умолчанию
-- первые четыре; остальное человек включает сам. Звонки в категории не входят
-- и приходят всегда.
-- Отключённая категория не создаёт строки в notifications и, значит, не шлёт
-- пуш; для сообщений и реакций на сообщения фильтрует сама push-send через
-- notify_push_filter. Тихие часы не отключают уведомление, а лишают его звука.

alter table notifications drop constraint notifications_kind_check;
alter table notifications add constraint notifications_kind_check check (kind in (
  'follow', 'comment', 'reply', 'reaction',
  'event_join', 'event_changed', 'event_cancelled', 'message',
  'quest_request', 'quest_join', 'quest_approved', 'quest_rejected',
  'quest_removed', 'quest_cancelled', 'need_response',
  'referral_joined', 'referral_reward', 'referral_confirmed', 'referral_cancelled',
  'mention'
));

alter table notifications drop constraint notifications_target_type_check;
alter table notifications add constraint notifications_target_type_check check (target_type in (
  'profile', 'post', 'event', 'place', 'route', 'quest', 'need', 'points', 'chat'
));

-- ── настройки ───────────────────────────────────────────────────────────────

create table notification_prefs (
  profile_id uuid primary key references profiles on delete cascade,
  -- Только то, что человек менял: {"follows": true, "likes": false}.
  settings   jsonb not null default '{}'::jsonb,
  -- Тихие часы: минуты от полуночи по местному времени; null — не заданы.
  quiet_from smallint check (quiet_from between 0 and 1439),
  quiet_to   smallint check (quiet_to between 0 and 1439),
  -- Сдвиг местного времени от UTC в минутах (телефон сообщает его сам).
  tz_offset  smallint not null default 0 check (tz_offset between -840 and 840),
  updated_at timestamptz not null default now()
);

alter table notification_prefs enable row level security;
revoke all on notification_prefs from public, anon, authenticated;

create function notification_category(in_kind text) returns text
language sql immutable set search_path = public as $$
  select case
    when in_kind = 'message' then 'messages'
    when in_kind in ('comment', 'reply') then 'comments'
    when in_kind = 'reaction' then 'likes'
    when in_kind = 'mention' then 'mentions'
    when in_kind = 'follow' then 'follows'
    when in_kind like 'event\_%' then 'events'
    when in_kind like 'quest\_%' then 'quests'
    when in_kind = 'need_response' then 'needs'
    when in_kind like 'referral\_%' then 'points'
    else 'other'
  end;
$$;

create function notify_enabled(in_profile uuid, in_category text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select (np.settings ->> in_category)::boolean
       from notification_prefs np where np.profile_id = in_profile),
    in_category in ('messages', 'comments', 'likes', 'mentions', 'other')
  );
$$;

create function notify_quiet_now(in_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case
      when np.quiet_from is null or np.quiet_to is null or np.quiet_from = np.quiet_to then false
      when np.quiet_from < np.quiet_to then t.m >= np.quiet_from and t.m < np.quiet_to
      else t.m >= np.quiet_from or t.m < np.quiet_to
    end
    from notification_prefs np,
         lateral (
           select (((extract(hour from now() at time zone 'utc')::int * 60
                     + extract(minute from now() at time zone 'utc')::int
                     + np.tz_offset) % 1440) + 1440) % 1440 as m
         ) t
    where np.profile_id = in_profile
  ), false);
$$;

-- Для push-send (service_role): кому из списка категория включена и у кого
-- сейчас тихие часы.
create function notify_push_filter(in_profiles uuid[], in_category text)
returns table (profile_id uuid, quiet boolean)
language sql stable security definer set search_path = public as $$
  select p, notify_quiet_now(p)
  from unnest(in_profiles) p
  where notify_enabled(p, in_category);
$$;

revoke all on function notification_category(text), notify_enabled(uuid, text),
  notify_quiet_now(uuid), notify_push_filter(uuid[], text) from public, anon, authenticated;
grant execute on function notification_category(text), notify_enabled(uuid, text),
  notify_quiet_now(uuid), notify_push_filter(uuid[], text) to service_role;

create function my_notification_prefs()
returns table (settings jsonb, quiet_from smallint, quiet_to smallint, tz_offset smallint)
language sql stable security definer set search_path = public as $$
  select np.settings, np.quiet_from, np.quiet_to, np.tz_offset
  from notification_prefs np where np.profile_id = auth.uid();
$$;

create function set_notification_prefs(
  in_settings jsonb,
  in_quiet_from smallint,
  in_quiet_to smallint,
  in_tz smallint
) returns void
language plpgsql security definer set search_path = public as $$
declare
  known text[] := array['messages', 'comments', 'likes', 'mentions', 'follows',
                        'events', 'quests', 'needs', 'points'];
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if jsonb_typeof(coalesce(in_settings, '{}'::jsonb)) <> 'object' then
    raise exception 'некорректные настройки';
  end if;
  if exists (
    select 1 from jsonb_each(coalesce(in_settings, '{}'::jsonb)) e
    where e.key <> all (known) or jsonb_typeof(e.value) <> 'boolean'
  ) then
    raise exception 'некорректные настройки';
  end if;

  insert into notification_prefs (profile_id, settings, quiet_from, quiet_to, tz_offset, updated_at)
  values (auth.uid(), coalesce(in_settings, '{}'::jsonb), in_quiet_from, in_quiet_to,
          coalesce(in_tz, 0), now())
  on conflict (profile_id) do update
    set settings = excluded.settings,
        quiet_from = excluded.quiet_from,
        quiet_to = excluded.quiet_to,
        tz_offset = excluded.tz_offset,
        updated_at = now();
end;
$$;

revoke all on function my_notification_prefs(), set_notification_prefs(jsonb, smallint, smallint, smallint)
  from public, anon;
grant execute on function my_notification_prefs(), set_notification_prefs(jsonb, smallint, smallint, smallint)
  to authenticated;

-- ── add_notification уважает настройки ──────────────────────────────────────

create or replace function add_notification(
  in_recipient uuid,
  in_actor uuid,
  in_kind text,
  in_target_type text,
  in_target uuid,
  in_title text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if in_recipient is null or in_recipient = in_actor then return; end if;
  if in_actor is not null and is_hidden_between(in_recipient, in_actor) then return; end if;
  if not notify_enabled(in_recipient, notification_category(in_kind)) then return; end if;

  -- Повторный лайк/отписка-подписка не должны сыпать одинаковыми строками.
  if exists (
    select 1 from notifications n
    where n.recipient_id = in_recipient
      and n.actor_id is not distinct from in_actor
      and n.kind = in_kind
      and n.target_id = in_target
      and n.read_at is null
  ) then return; end if;

  insert into notifications (recipient_id, actor_id, kind, target_type, target_id, title)
  values (in_recipient, in_actor, in_kind, in_target_type, in_target, left(in_title, 120));
end;
$$;

-- ── упоминания @ник ─────────────────────────────────────────────────────────
-- Пост виден упомянутому, только если он вообще может его открыть: публичный,
-- либо для подписчиков и человек подписан. Чат — только если он его участник.

create function notify_mentions(
  in_text text,
  in_author uuid,
  in_target_type text,
  in_target uuid,
  in_post uuid default null,
  in_conversation uuid default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  uname text;
  rid uuid;
  vis text;
  post_author uuid;
begin
  if coalesce(in_text, '') !~ '@[A-Za-z0-9_]{3,20}' then return; end if;

  if in_post is not null then
    select p.visibility, p.author_id into vis, post_author
    from posts p where p.id = in_post and p.status = 'active';
    if vis is null then return; end if;
  end if;

  for uname in
    select distinct lower(m[1])
    from regexp_matches(in_text, '(?:^|[^A-Za-z0-9_@])@([A-Za-z0-9_]{3,20})', 'g') as m
    limit 10
  loop
    select id into rid from profiles where username = uname and status <> 'blocked';
    continue when rid is null or rid = in_author;

    if in_post is not null and not (
      vis = 'public'
      or (vis = 'followers' and (
        rid = post_author
        or exists (
          select 1 from follows f
          where f.follower_id = rid and f.target_type = 'profile' and f.target_id = post_author
        )
      ))
    ) then
      continue;
    end if;

    if in_conversation is not null and not exists (
      select 1 from chat_members cm
      where cm.conversation_id = in_conversation and cm.profile_id = rid
    ) then
      continue;
    end if;

    perform add_notification(rid, in_author, 'mention', in_target_type, in_target,
                             left(btrim(in_text), 120));
  end loop;
end;
$$;

revoke all on function notify_mentions(text, uuid, text, uuid, uuid, uuid)
  from public, anon, authenticated;

create function trg_mentions_post() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_mentions(coalesce(new.title, '') || ' ' || coalesce(new.body, ''),
                          new.author_id, 'post', new.id, new.id);
  return null;
end;
$$;

create function trg_mentions_comment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_mentions(new.body, new.author_id, 'post', new.post_id, new.post_id);
  return null;
end;
$$;

-- Только группы и квест-чаты: у личных диалогов текст зашифрован, body пуст,
-- а в каналах упоминание не имеет смысла.
create function trg_mentions_chat_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.body is null then return null; end if;
  if exists (
    select 1 from chat_conversations c
    where c.id = new.conversation_id and (c.direct_key is not null or c.is_channel)
  ) then
    return null;
  end if;
  perform notify_mentions(new.body, new.sender_id, 'chat', new.conversation_id,
                          null, new.conversation_id);
  return null;
end;
$$;

revoke all on function trg_mentions_post(), trg_mentions_comment(), trg_mentions_chat_message()
  from public, anon, authenticated;

create trigger mentions_on_post after insert on posts
  for each row execute function trg_mentions_post();
create trigger mentions_on_comment after insert on post_comments
  for each row execute function trg_mentions_comment();
create trigger mentions_on_chat_message after insert on chat_messages
  for each row execute function trg_mentions_chat_message();
