-- «Взять задачу»: свободную (без исполнителя) задачу может забрать любой
-- участник, и она закрепляется за ним. Плюс «отказаться» от своей.
--
-- Триггер ws_tasks_before запрещает участнику менять исполнителя (это право
-- админов), поэтому обе функции на время своей транзакции поднимают флаг
-- ws.claiming. Клиент через REST выставить GUC в одной транзакции с UPDATE
-- не может. Зависит от 0017.

create or replace function ws_tasks_before() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then new.creator_id := auth.uid(); end if;
    if new.status = 'done' then new.completed_at := now(); end if;
    return new;
  end if;

  if new.workspace_id <> old.workspace_id or new.project_id <> old.project_id
     or new.creator_id is distinct from old.creator_id then
    raise exception 'workspace, project и автора задачи менять нельзя';
  end if;

  -- обычный участник правит только свои задачи и только разрешённые поля
  if auth.uid() is not null and not ws_is_admin(old.workspace_id)
     and coalesce(current_setting('ws.claiming', true), '') <> '1' then
    if old.assignee_id is distinct from auth.uid() then
      raise exception 'участник может менять только задачи, назначенные на него';
    end if;
    if new.title <> old.title or new.priority <> old.priority
       or new.assignee_id is distinct from old.assignee_id
       or new.due_date is distinct from old.due_date
       or new.archived_at is distinct from old.archived_at then
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

-- Атомарно: UPDATE ... WHERE assignee_id IS NULL под блокировкой строки, поэтому
-- при одновременном «взять» второй получит 0 строк и ошибку, а не перезапишет.
create function ws_claim_task(p_task uuid) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare n int;
begin
  if auth.uid() is null or not ws_is_member(ws_task_ws(p_task)) then
    raise exception 'нет доступа';
  end if;
  perform set_config('ws.claiming', '1', true);
  update ws_tasks
     set assignee_id = auth.uid(),
         status = case when status in ('backlog', 'todo') then 'in_progress' else status end
   where id = p_task and assignee_id is null and archived_at is null and status <> 'done';
  get diagnostics n = row_count;
  perform set_config('ws.claiming', '', true);
  if n = 0 then
    raise exception 'задачу уже взял кто-то другой, либо она закрыта';
  end if;
end
$$;

-- Отказаться может исполнитель (и админ за любого): задача снова свободна,
-- «в работе» возвращается в To Do.
create function ws_release_task(p_task uuid) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare n int;
begin
  if auth.uid() is null or not ws_is_member(ws_task_ws(p_task)) then
    raise exception 'нет доступа';
  end if;
  perform set_config('ws.claiming', '1', true);
  update ws_tasks
     set assignee_id = null,
         status = case when status = 'in_progress' then 'todo' else status end
   where id = p_task and assignee_id is not null and archived_at is null
     and (assignee_id = auth.uid() or ws_is_admin(workspace_id));
  get diagnostics n = row_count;
  perform set_config('ws.claiming', '', true);
  if n = 0 then
    raise exception 'отказаться можно только от своей задачи';
  end if;
end
$$;

grant execute on function ws_claim_task, ws_release_task to authenticated;
