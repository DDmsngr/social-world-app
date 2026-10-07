-- 0054: подзадачи в задачах панели команды (Chawo Workspace). Перенос из First
-- Logic (его 0025): одна задача с чек-листом проверок вместо кучи отдельных
-- карточек. Подзадача — та же ws_tasks со ссылкой на родителя; один уровень
-- вложенности; счётчики subtask_total/subtask_done ведёт триггер.
-- Зависит от 0017 и 0020 (ws_tasks_before с флагом ws.claiming сохранён).
alter table ws_tasks
  add column parent_id     uuid references ws_tasks(id) on delete cascade,
  add column subtask_total int not null default 0 check (subtask_total >= 0),
  add column subtask_done  int not null default 0 check (subtask_done >= 0 and subtask_done <= subtask_total);
create index ws_tasks_parent_idx on ws_tasks (parent_id) where parent_id is not null;

-- ── правила для parent_id + системный пересчёт счётчиков ────────────────────

create or replace function ws_tasks_before() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  v_parent ws_tasks;
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then new.creator_id := auth.uid(); end if;
    if new.status = 'done' then new.completed_at := now(); end if;
    if new.parent_id is not null then
      if new.parent_id = new.id then raise exception 'задача не может быть подзадачей самой себе'; end if;
      select * into v_parent from ws_tasks where id = new.parent_id;
      if v_parent.id is null then raise exception 'родительская задача не найдена'; end if;
      if v_parent.workspace_id <> new.workspace_id or v_parent.project_id <> new.project_id then
        raise exception 'подзадача должна быть в том же проекте, что и родительская задача';
      end if;
      if v_parent.parent_id is not null then
        raise exception 'подзадачи нельзя вкладывать друг в друга — не больше одного уровня';
      end if;
    end if;
    return new;
  end if;

  -- системный пересчёт subtask_total/subtask_done (см. ws_tasks_recount_subtasks) —
  -- не пользовательское действие, обычные ограничения к нему не применяются
  if current_setting('ws.subtask_sync', true) = '1' then
    return new;
  end if;

  if new.workspace_id <> old.workspace_id or new.project_id <> old.project_id
     or new.creator_id is distinct from old.creator_id then
    raise exception 'workspace, project и автора задачи менять нельзя';
  end if;

  if new.parent_id is distinct from old.parent_id then
    if exists (select 1 from ws_tasks where parent_id = old.id) then
      raise exception 'у задачи уже есть подзадачи — сначала откройте их';
    end if;
    if new.parent_id is not null then
      if new.parent_id = old.id then raise exception 'задача не может быть подзадачей самой себе'; end if;
      select * into v_parent from ws_tasks where id = new.parent_id;
      if v_parent.id is null then raise exception 'родительская задача не найдена'; end if;
      if v_parent.workspace_id <> new.workspace_id or v_parent.project_id <> new.project_id then
        raise exception 'подзадача должна быть в том же проекте, что и родительская задача';
      end if;
      if v_parent.parent_id is not null then
        raise exception 'подзадачи нельзя вкладывать друг в друга — не больше одного уровня';
      end if;
    end if;
  end if;

  -- обычный участник правит только свои задачи и только разрешённые поля;
  -- ws.claiming — флаг «Взять»/«Отказаться» (0004), меняющих исполнителя не по этому правилу
  if auth.uid() is not null and not ws_is_admin(old.workspace_id)
     and coalesce(current_setting('ws.claiming', true), '') <> '1' then
    if old.assignee_id is distinct from auth.uid() then
      raise exception 'участник может менять только задачи, назначенные на него';
    end if;
    if new.title <> old.title or new.priority <> old.priority
       or new.assignee_id is distinct from old.assignee_id
       or new.due_date is distinct from old.due_date
       or new.archived_at is distinct from old.archived_at
       or new.parent_id is distinct from old.parent_id then
      raise exception 'участнику доступны статус, описание и порядок; остальное — админам';
    end if;
  end if;

  new.updated_at := now();
  if new.status is distinct from old.status then
    new.completed_at := case when new.status = 'done' then now() else null end;
  end if;
  return new;
end
$$;

create function ws_tasks_recount_subtasks(p_parent uuid) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  perform set_config('ws.subtask_sync', '1', true);
  update ws_tasks set
    subtask_total = (select count(*) from ws_tasks c where c.parent_id = p_parent and c.archived_at is null),
    subtask_done  = (select count(*) from ws_tasks c where c.parent_id = p_parent and c.archived_at is null and c.status = 'done')
  where id = p_parent;
  perform set_config('ws.subtask_sync', '', true);
end
$$;

create function ws_tasks_subtask_sync() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if tg_op = 'DELETE' then
    if old.parent_id is not null then perform ws_tasks_recount_subtasks(old.parent_id); end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.parent_id is not null then perform ws_tasks_recount_subtasks(new.parent_id); end if;
    return new;
  end if;
  if old.parent_id is distinct from new.parent_id then
    if old.parent_id is not null then perform ws_tasks_recount_subtasks(old.parent_id); end if;
    if new.parent_id is not null then perform ws_tasks_recount_subtasks(new.parent_id); end if;
  elsif new.parent_id is not null and (old.status is distinct from new.status or old.archived_at is distinct from new.archived_at) then
    perform ws_tasks_recount_subtasks(new.parent_id);
  end if;
  return new;
end
$$;
-- только по этим колонкам — иначе пересчёт (который трогает только сами счётчики)
-- запускал бы сам себя по кругу
create trigger ws_tasks_subtask_sync after insert or delete or update of status, parent_id, archived_at on ws_tasks
  for each row execute function ws_tasks_subtask_sync();

-- Обзор и доска: подзадачи не считаются отдельными карточками.
create or replace function ws_project_stats(p_project uuid) returns jsonb
language sql stable
as $$
  select jsonb_build_object(
    'total',       count(*),
    'backlog',     count(*) filter (where status = 'backlog'),
    'todo',        count(*) filter (where status = 'todo'),
    'in_progress', count(*) filter (where status = 'in_progress'),
    'review',      count(*) filter (where status = 'review'),
    'blocked',     count(*) filter (where status = 'blocked'),
    'done',        count(*) filter (where status = 'done'),
    'overdue',     count(*) filter (where status <> 'done' and due_date < current_date)
  )
  from ws_tasks where project_id = p_project and archived_at is null and parent_id is null
$$;

-- Быстрое добавление подзадач списком (по одной на строку) — чек-лист проверок.
create function ws_task_add_subtasks(p_parent uuid, p_titles text[]) returns jsonb
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  pt ws_tasks;
  v_title text;
  v_id uuid;
  v_num int;
  v_out jsonb := '[]'::jsonb;
begin
  select * into pt from ws_tasks where id = p_parent;
  if pt.id is null then raise exception 'задача не найдена'; end if;
  if not ws_is_admin(pt.workspace_id) then raise exception 'подзадачи создают только owner и admin'; end if;
  if pt.parent_id is not null then raise exception 'у подзадачи не может быть своих подзадач'; end if;
  if p_titles is null or array_length(p_titles, 1) is null then raise exception 'нет названий подзадач'; end if;
  if array_length(p_titles, 1) > 100 then raise exception 'не больше 100 подзадач за раз'; end if;

  foreach v_title in array p_titles loop
    v_title := trim(v_title);
    continue when v_title = '';
    if length(v_title) > 200 then raise exception 'название длиннее 200 символов: «%»', v_title; end if;
    insert into ws_tasks (workspace_id, project_id, parent_id, title, status)
    values (pt.workspace_id, pt.project_id, pt.id, v_title, 'todo')
    returning id, num into v_id, v_num;
    v_out := v_out || jsonb_build_object('id', v_id, 'num', v_num, 'title', v_title);
  end loop;

  if jsonb_array_length(v_out) = 0 then raise exception 'все строки были пустыми'; end if;
  return v_out;
end
$$;

revoke all on function ws_task_add_subtasks, ws_tasks_recount_subtasks, ws_tasks_subtask_sync from public, anon, authenticated;
grant execute on function ws_task_add_subtasks to authenticated;
