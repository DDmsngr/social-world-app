-- 0055: профиль участника (должность, телефон, фото) и видимость активности
-- (всегда / в рабочее время / никогда) в панели команды. Перенос из First Logic
-- (его 0006 и 0017). Зависит от 0017, 0018 (ws_members_guard с флагом
-- ws.accepting сохранён) и 0028.

-- ── профиль ─────────────────────────────────────────────────────────────────
-- Профиль участника: должность, телефон, фото.
--
-- Свой профиль правит сам участник; роль и статус по-прежнему только через
-- ws_members_guard. Права на колонки выдаются явно (см. 0001: сначала revoke all).

alter table ws_members
  add column position text check (position is null or length(position) <= 80),
  add column phone    text check (phone is null or length(phone) <= 40);

grant update (name, avatar_url, position, phone) on ws_members to authenticated;

create policy "участник правит свой профиль" on ws_members
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Политика админов даёт им право менять строки, поэтому чужие профильные поля
-- закрываем триггером: админ правит только незанятые приглашения (имя до входа).
create or replace function ws_members_guard() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is null then return new; end if;  -- сервисный доступ
  if current_setting('ws.accepting', true) = '1' then return new; end if;
  if (new.name, new.avatar_url, new.position, new.phone)
       is distinct from (old.name, old.avatar_url, old.position, old.phone)
     and old.user_id is not null and old.user_id <> auth.uid() then
    raise exception 'профиль правит только сам участник';
  end if;
  if new.role is distinct from old.role or new.status is distinct from old.status then
    if old.user_id = auth.uid() then
      raise exception 'свою роль и статус менять нельзя';
    end if;
    if old.role = 'owner' or new.role = 'owner' then
      raise exception 'роль owner не меняется через интерфейс';
    end if;
    if new.role = 'admin' and ws_role(old.workspace_id) <> 'owner' then
      raise exception 'администраторов назначает только owner';
    end if;
    if old.status = 'invited' and new.status <> 'invited' then
      raise exception 'приглашённый становится активным только по токену';
    end if;
  end if;
  return new;
end
$$;

-- ── фото ────────────────────────────────────────────────────────────────────
-- Публичный бакет: аватар показывается обычным <img> без подписанных ссылок.
-- Имена файлов не угадываются (<user_id>/<время>.jpg), а сами фото не секрет.
-- Клиент уменьшает снимок до 256×256, поэтому лимит маленький.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "avatars: свои файлы видно владельцу" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text);

create policy "avatars: грузить только в свою папку" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text);

create policy "avatars: удалять только свои" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text);

-- ── видимость активности ────────────────────────────────────────────────────

-- Видимость активности: всегда / по расписанию / никогда.
-- Скрываем на сервере: вне разрешённого времени ws_touch просто не пишет last_seen,
-- в режиме «никогда» last_seen стирается. Остальные видят «скрыта» или последнее
-- время, когда участник был виден.

alter table ws_members
  add column presence_mode text not null default 'always' check (presence_mode in ('always', 'schedule', 'never')),
  add column presence_from time not null default '09:00',
  add column presence_to   time not null default '19:00',
  add column presence_tz   text not null default 'Europe/Moscow' check (length(presence_tz) <= 64);

grant update (presence_mode, presence_from, presence_to, presence_tz) on ws_members to authenticated;

-- Окно через полночь (22:00–06:00) тоже поддерживается.
create function ws_presence_visible(p_mode text, p_from time, p_to time, p_tz text) returns boolean
language plpgsql stable
set search_path = public
as $$
declare t time;
begin
  if p_mode = 'always' then return true; end if;
  if p_mode = 'never' then return false; end if;
  begin
    t := (now() at time zone p_tz)::time;
  exception when others then
    t := (now() at time zone 'Europe/Moscow')::time;
  end;
  if p_from <= p_to then return t >= p_from and t < p_to; end if;
  return t >= p_from or t < p_to;
end
$$;

create or replace function ws_touch(p_ws uuid) returns void
language sql security definer
set search_path = public
set row_security = off
as $$
  update ws_members set last_seen = now()
  where workspace_id = p_ws and user_id = auth.uid() and status = 'active'
    and (last_seen is null or last_seen < now() - interval '1 minute')
    and ws_presence_visible(presence_mode, presence_from, presence_to, presence_tz)
$$;

-- Чужую видимость не меняет никто, включая админов (их политика даёт update строки).
create function ws_members_presence_guard() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is not null
     and (new.presence_mode, new.presence_from, new.presence_to, new.presence_tz)
         is distinct from (old.presence_mode, old.presence_from, old.presence_to, old.presence_tz)
     and old.user_id is distinct from auth.uid() then
    raise exception 'видимость активности меняет только сам участник';
  end if;
  if new.presence_mode = 'never' then new.last_seen := null; end if;
  return new;
end
$$;

create trigger ws_members_presence_guard before update on ws_members
  for each row execute function ws_members_presence_guard();

revoke execute on function ws_presence_visible, ws_members_presence_guard from public, anon;
grant execute on function ws_presence_visible to authenticated, service_role;
