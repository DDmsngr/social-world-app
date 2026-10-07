-- 0057: личные настройки чата — архив, «удалён у меня», свой звук и фон — и
-- предложение фона собеседнику («выбрал для двоих»: тот принимает или нет).
--
-- Отдельная таблица, а не колонки my_chats: список чатов остаётся как есть,
-- клиент накладывает настройки сам. «Удалить чат» здесь — убрать у себя:
-- история до cleared_at скрыта, чат вернётся, когда придёт новое сообщение.
-- У собеседника ничего не пропадает.

create table chat_settings (
  profile_id      uuid not null references profiles on delete cascade,
  conversation_id uuid not null references chat_conversations on delete cascade,
  archived_at     timestamptz,
  cleared_at      timestamptz,
  sound           text check (sound is null or sound in ('ding', 'pop', 'chime', 'drop', 'knock')),
  wallpaper       text check (wallpaper is null or char_length(wallpaper) <= 40),
  updated_at      timestamptz not null default now(),
  primary key (profile_id, conversation_id)
);

alter table chat_settings enable row level security;
revoke all on chat_settings from public, anon, authenticated;
grant select on chat_settings to service_role;

create function chat_member_check(p_conversation uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if not exists (
    select 1 from chat_members
    where conversation_id = p_conversation and profile_id = auth.uid()
  ) then
    raise exception 'вы не участник этого чата';
  end if;
end $$;
revoke all on function chat_member_check(uuid) from public, anon, authenticated;

-- Все мои настройки разом: список чатов и экран чата берут их одним запросом.
create function my_chat_settings()
returns table (
  conversation_id uuid, archived_at timestamptz, cleared_at timestamptz,
  sound text, wallpaper text
)
language sql stable security definer set search_path = public as $$
  select s.conversation_id, s.archived_at, s.cleared_at, s.sound, s.wallpaper
  from chat_settings s
  where s.profile_id = auth.uid();
$$;

create function set_chat_archived(p_conversation uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform chat_member_check(p_conversation);
  insert into chat_settings (profile_id, conversation_id, archived_at)
  values (auth.uid(), p_conversation, case when p_archived then now() end)
  on conflict (profile_id, conversation_id) do update
    set archived_at = case when p_archived then now() end, updated_at = now();
end $$;

-- «Удалить чат у себя»: скрыть всё, что было до этого момента.
create function clear_chat_for_me(p_conversation uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform chat_member_check(p_conversation);
  insert into chat_settings (profile_id, conversation_id, cleared_at)
  values (auth.uid(), p_conversation, now())
  on conflict (profile_id, conversation_id) do update
    set cleared_at = now(), archived_at = null, updated_at = now();
end $$;

-- Звук и фон. null — как по умолчанию.
create function set_chat_look(p_conversation uuid, p_sound text, p_wallpaper text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform chat_member_check(p_conversation);
  insert into chat_settings (profile_id, conversation_id, sound, wallpaper)
  values (auth.uid(), p_conversation, p_sound, p_wallpaper)
  on conflict (profile_id, conversation_id) do update
    set sound = excluded.sound, wallpaper = excluded.wallpaper, updated_at = now();
end $$;

revoke all on function my_chat_settings(), set_chat_archived(uuid, boolean),
  clear_chat_for_me(uuid), set_chat_look(uuid, text, text) from public, anon;
grant execute on function my_chat_settings(), set_chat_archived(uuid, boolean),
  clear_chat_for_me(uuid), set_chat_look(uuid, text, text) to authenticated;

-- ── предложение фона собеседнику ────────────────────────────────────────────

create table chat_wallpaper_offers (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references chat_conversations on delete cascade,
  from_id         uuid not null references profiles on delete cascade,
  to_id           uuid not null references profiles on delete cascade,
  wallpaper       text not null check (char_length(wallpaper) <= 40),
  status          text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at      timestamptz not null default now()
);
create index chat_wallpaper_offers_conv_idx on chat_wallpaper_offers (conversation_id, created_at desc);

alter table chat_wallpaper_offers enable row level security;
revoke all on chat_wallpaper_offers from public, anon, authenticated;
grant select on chat_wallpaper_offers to authenticated;

create policy "предложения фона видят двое" on chat_wallpaper_offers
  for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());

alter publication supabase_realtime add table chat_wallpaper_offers;

-- Мой фон ставится сразу, собеседнику уходит предложение (только личные чаты).
create function offer_chat_wallpaper(p_conversation uuid, p_wallpaper text) returns void
language plpgsql security definer set search_path = public as $$
declare v_peer uuid;
begin
  perform chat_member_check(p_conversation);
  if not exists (
    select 1 from chat_conversations where id = p_conversation and direct_key is not null
  ) then
    raise exception 'предложить фон можно только в личном чате';
  end if;
  select profile_id into v_peer from chat_members
  where conversation_id = p_conversation and profile_id <> auth.uid() limit 1;
  if v_peer is null then raise exception 'собеседник не найден'; end if;

  insert into chat_settings (profile_id, conversation_id, wallpaper)
  values (auth.uid(), p_conversation, p_wallpaper)
  on conflict (profile_id, conversation_id) do update
    set wallpaper = excluded.wallpaper, updated_at = now();

  -- Старые неотвеченные предложения от меня снимаем: актуально последнее.
  delete from chat_wallpaper_offers
  where conversation_id = p_conversation and from_id = auth.uid() and status = 'pending';
  insert into chat_wallpaper_offers (conversation_id, from_id, to_id, wallpaper)
  values (p_conversation, auth.uid(), v_peer, p_wallpaper);
end $$;

create function respond_chat_wallpaper(p_offer uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare o chat_wallpaper_offers;
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  select * into o from chat_wallpaper_offers
  where id = p_offer and to_id = auth.uid() and status = 'pending';
  if o.id is null then raise exception 'предложение не найдено'; end if;
  update chat_wallpaper_offers set status = case when p_accept then 'accepted' else 'declined' end
  where id = o.id;
  if p_accept then
    insert into chat_settings (profile_id, conversation_id, wallpaper)
    values (auth.uid(), o.conversation_id, o.wallpaper)
    on conflict (profile_id, conversation_id) do update
      set wallpaper = excluded.wallpaper, updated_at = now();
  end if;
end $$;

revoke all on function offer_chat_wallpaper(uuid, text), respond_chat_wallpaper(uuid, boolean)
  from public, anon;
grant execute on function offer_chat_wallpaper(uuid, text), respond_chat_wallpaper(uuid, boolean)
  to authenticated;
