-- Карта приложения Chawo в Team Workspace.
--
-- Дерево модулей, экранов и фич приложения: у каждого узла статус готовности,
-- ответственный, версия сборки, в которой он появился, и привязанные задачи.
-- Аналог «Узлов и состава» из first-logic, только вместо железа — код:
-- «Чат» → «Список чатов» → «Ответ свайпом». Готовность родителя считается
-- на клиенте по потомкам, в базе хранятся только сами узлы.
-- Зависит от 0017 (ws_*) и 0022 (релизы).

create table cw_modules (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  parent_id     uuid references cw_modules(id) on delete cascade,
  kind          text not null default 'feature'
                  check (kind in ('module', 'screen', 'feature', 'service')),
  name          text not null check (length(trim(name)) between 1 and 120),
  description   text not null default '',
  status        text not null default 'idea'
                  check (status in ('idea', 'planned', 'in_dev', 'beta', 'live', 'deprecated')),
  owner_id      uuid references auth.users(id) on delete set null,
  -- сборка (ws_app_releases.version_code), с которой узел есть у пользователей
  release_code  integer,
  repo_path     text not null default '',
  position      int not null default 0,
  created_by    uuid references auth.users(id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  archived_at   timestamptz,
  check (parent_id is distinct from id)
);
create index cw_modules_ws_idx on cw_modules (workspace_id, parent_id, position);

create table cw_module_tasks (
  module_id  uuid not null references cw_modules(id) on delete cascade,
  task_id    uuid not null references ws_tasks(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (module_id, task_id)
);
create index cw_module_tasks_task_idx on cw_module_tasks (task_id);

create function cw_modules_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end
$$;
create trigger cw_modules_touch before update on cw_modules
  for each row execute function cw_modules_touch();

-- Родитель из того же workspace и без циклов. Триггер назван не cw_modules_check:
-- это имя занимает автоконстрейнт check (parent_id is distinct from id).
-- Constraint-trigger отложенный:
-- шаблон карты вставляется одним запросом, где потомок может идти раньше родителя.
create function cw_modules_check() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if new.parent_id is null then return null; end if;
  if not exists (select 1 from cw_modules where id = new.parent_id and workspace_id = new.workspace_id) then
    raise exception 'родитель узла не найден в этом пространстве';
  end if;
  if exists (
    with recursive up(id) as (
      select new.parent_id
      union
      select m.parent_id from cw_modules m join up u on m.id = u.id where m.parent_id is not null
    )
    select 1 from up where id = new.id
  ) then
    raise exception 'узел не может оказаться внутри самого себя';
  end if;
  return null;
end
$$;
create constraint trigger cw_modules_tree_check after insert or update of parent_id on cw_modules
  deferrable initially deferred
  for each row execute function cw_modules_check();

-- Задача и узел — из одного workspace.
create function cw_module_tasks_check() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if (select workspace_id from cw_modules where id = new.module_id)
     is distinct from (select workspace_id from ws_tasks where id = new.task_id) then
    raise exception 'задача и узел из разных пространств';
  end if;
  return new;
end
$$;
create trigger cw_module_tasks_check before insert on cw_module_tasks
  for each row execute function cw_module_tasks_check();

alter table cw_modules enable row level security;
alter table cw_module_tasks enable row level security;

create policy "карту видят участники" on cw_modules
  for select to authenticated using (ws_is_member(workspace_id));
create policy "карту правят участники" on cw_modules
  for insert to authenticated
  with check (ws_role(workspace_id) in ('owner', 'admin', 'member'));
create policy "карту меняют участники" on cw_modules
  for update to authenticated
  using (ws_role(workspace_id) in ('owner', 'admin', 'member'))
  with check (ws_role(workspace_id) in ('owner', 'admin', 'member'));
create policy "узел удаляют админы" on cw_modules
  for delete to authenticated using (ws_is_admin(workspace_id));

create policy "связи видят участники" on cw_module_tasks
  for select to authenticated using (exists (
    select 1 from cw_modules m where m.id = module_id and ws_is_member(m.workspace_id)));
create policy "связи добавляют участники" on cw_module_tasks
  for insert to authenticated with check (exists (
    select 1 from cw_modules m where m.id = module_id
      and ws_role(m.workspace_id) in ('owner', 'admin', 'member')));
create policy "связи убирают участники" on cw_module_tasks
  for delete to authenticated using (exists (
    select 1 from cw_modules m where m.id = module_id
      and ws_role(m.workspace_id) in ('owner', 'admin', 'member')));

revoke all on cw_modules, cw_module_tasks from anon;
grant select, insert, update, delete on cw_modules, cw_module_tasks to authenticated;
revoke execute on function cw_modules_touch, cw_modules_check, cw_module_tasks_check from public, anon;
grant execute on function cw_modules_check, cw_module_tasks_check to authenticated;

alter publication supabase_realtime add table cw_modules;
