-- Релизы APK в Team Workspace: список сборок с описанием «что сделано».
--
-- Файлы лежат в публичном бакете app-releases (0007), здесь только каталог.
-- Строку добавляет CI после публикации APK через ws_publish_release — эта
-- функция закрыта от anon/authenticated, вызвать её может только service_role.
-- Описание (notes) CI заполняет черновиком из коммитов, дальше его правят
-- owner/admin прямо в дашборде. Повторный запуск CI по той же сборке правленое
-- описание не затирает. Зависит от 0017.

create table ws_app_releases (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  version_code  integer not null,
  version_name  text not null,
  apk_url       text not null,
  size_bytes    bigint,
  commit_sha    text,
  notes         text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (workspace_id, version_code)
);

create index ws_app_releases_list on ws_app_releases (workspace_id, version_code desc);

alter table ws_app_releases enable row level security;

create policy "релизы видят участники" on ws_app_releases
  for select to authenticated using (ws_is_member(workspace_id));
create policy "описание релиза правят админы" on ws_app_releases
  for update to authenticated using (ws_is_admin(workspace_id)) with check (ws_is_admin(workspace_id));

-- Через REST можно менять только описание; всё остальное — только CI.
revoke insert, update, delete on ws_app_releases from authenticated, anon;
grant update (notes) on ws_app_releases to authenticated;

create function ws_app_releases_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create trigger ws_app_releases_touch before update on ws_app_releases
  for each row execute function ws_app_releases_touch();

create function ws_publish_release(
  p_version_code integer,
  p_version_name text,
  p_apk_url text,
  p_size bigint,
  p_commit text,
  p_notes text
) returns uuid
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  v_ws uuid;
  v_id uuid;
begin
  select id into v_ws from ws_workspaces where slug = 'social-world';
  if v_ws is null then
    raise exception 'workspace social-world не найден';
  end if;

  insert into ws_app_releases (workspace_id, version_code, version_name, apk_url, size_bytes, commit_sha, notes)
  values (v_ws, p_version_code, p_version_name, p_apk_url, p_size, p_commit, coalesce(p_notes, ''))
  on conflict (workspace_id, version_code) do update
    set version_name = excluded.version_name,
        apk_url = excluded.apk_url,
        size_bytes = excluded.size_bytes,
        commit_sha = excluded.commit_sha
  returning id into v_id;

  return v_id;
end
$$;

revoke all on function ws_publish_release(integer, text, text, bigint, text, text) from public, anon, authenticated;
grant execute on function ws_publish_release(integer, text, text, bigint, text, text) to service_role;
