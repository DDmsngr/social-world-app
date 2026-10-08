-- Групповые чаты, номера задач (#N), задача как вложение сообщения,
-- realtime для меток и файлов.
--
-- Зависит от 0017/0018.

-- ── номера задач: сквозные внутри проекта ───────────────────────────────────

alter table ws_projects add column task_counter integer not null default 0;
alter table ws_tasks add column num integer;

update ws_tasks t set num = r.n
from (select id, row_number() over (partition by project_id order by created_at, id) n from ws_tasks) r
where r.id = t.id;

update ws_projects p set task_counter = coalesce((select max(num) from ws_tasks t where t.project_id = p.id), 0);

alter table ws_tasks alter column num set not null;
create unique index ws_tasks_num_uq on ws_tasks (project_id, num);

create function ws_tasks_num() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  update ws_projects set task_counter = task_counter + 1
  where id = new.project_id
  returning task_counter into new.num;
  return new;
end
$$;
create trigger ws_tasks_num before insert on ws_tasks
  for each row execute function ws_tasks_num();

-- ── группы и вложенная задача ───────────────────────────────────────────────

alter table ws_conversations drop constraint ws_conversations_kind_check;
alter table ws_conversations add constraint ws_conversations_kind_check
  check (kind in ('channel', 'direct', 'group'));
alter table ws_conversations add column created_by uuid references auth.users(id) on delete set null;

alter table ws_messages add column task_id uuid references ws_tasks(id) on delete set null;

create or replace function ws_messages_before() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if tg_op = 'INSERT' then
    select workspace_id into new.workspace_id from ws_conversations where id = new.conversation_id;
    if auth.uid() is not null then new.author_id := auth.uid(); end if;
    if new.task_id is not null and ws_task_ws(new.task_id) is distinct from new.workspace_id then
      raise exception 'задача из другого workspace';
    end if;
  else
    if new.conversation_id <> old.conversation_id or new.author_id is distinct from old.author_id
       or new.task_id is distinct from old.task_id then
      raise exception 'привязку сообщения менять нельзя';
    end if;
    if new.body is distinct from old.body and new.deleted_at is null then
      new.edited_at := now();
    end if;
  end if;
  return new;
end
$$;

-- Создать группу: создатель + выбранные активные участники workspace.
create function ws_create_group(p_ws uuid, p_name text, p_members uuid[]) returns uuid
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare v_id uuid;
begin
  if not ws_is_member(p_ws) then raise exception 'нет доступа'; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'у группы должно быть название'; end if;
  insert into ws_conversations (workspace_id, kind, name, created_by)
  values (p_ws, 'group', trim(p_name), auth.uid()) returning id into v_id;
  insert into ws_conversation_members (conversation_id, user_id)
  select v_id, u from (
    select auth.uid() as u
    union
    select m.user_id from ws_members m
    where m.workspace_id = p_ws and m.status = 'active' and m.user_id = any(coalesce(p_members, '{}'))
  ) s where u is not null;
  return v_id;
end
$$;

-- Добавить людей в группу может любой её участник.
create function ws_group_add_members(p_conv uuid, p_members uuid[]) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare c ws_conversations;
begin
  select * into c from ws_conversations where id = p_conv;
  if c.id is null or c.kind <> 'group' then raise exception 'это не группа'; end if;
  if not ws_can_read_conv(p_conv) then raise exception 'нет доступа'; end if;
  insert into ws_conversation_members (conversation_id, user_id)
  select p_conv, m.user_id from ws_members m
  where m.workspace_id = c.workspace_id and m.status = 'active' and m.user_id = any(coalesce(p_members, '{}'))
  on conflict do nothing;
end
$$;

-- Кто в диалоге (для заголовка группы); видно только тем, кто сам в нём.
create function ws_conv_members(p_conv uuid) returns setof uuid
language sql stable security definer
set search_path = public
set row_security = off
as $$
  select user_id from ws_conversation_members
  where conversation_id = p_conv and ws_can_read_conv(p_conv)
$$;

grant execute on function ws_create_group, ws_group_add_members, ws_conv_members to authenticated;

-- ── поиск: по номеру задачи тоже ────────────────────────────────────────────

create or replace function ws_search(p_ws uuid, p_q text) returns jsonb
language plpgsql stable
as $$
declare
  v_like text := '%' || replace(replace(replace(trim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_num  text := ltrim(trim(p_q), '#');
begin
  if length(trim(p_q)) < 2 and v_num !~ '^\d+$' then
    return jsonb_build_object('tasks', '[]'::jsonb, 'members', '[]'::jsonb,
                              'messages', '[]'::jsonb, 'files', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'tasks', coalesce((select jsonb_agg(x) from (
      select id, num, title, status from ws_tasks
      where workspace_id = p_ws and archived_at is null
        and (title ilike v_like or description ilike v_like or num::text = v_num)
      order by updated_at desc limit 8) x), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(x) from (
      select user_id, name, email, role from ws_members
      where workspace_id = p_ws and status = 'active' and (name ilike v_like or email ilike v_like)
      limit 8) x), '[]'::jsonb),
    'messages', coalesce((select jsonb_agg(x) from (
      select id, conversation_id, body, created_at from ws_messages
      where workspace_id = p_ws and deleted_at is null and body ilike v_like
      order by created_at desc limit 8) x), '[]'::jsonb),
    'files', coalesce((select jsonb_agg(x) from (
      select id, task_id, filename, size from ws_attachments
      where workspace_id = p_ws and filename ilike v_like
      order by created_at desc limit 8) x), '[]'::jsonb)
  );
end
$$;

-- ── realtime: метки, файлы, новые диалоги ───────────────────────────────────

alter publication supabase_realtime add table ws_task_labels, ws_attachments, ws_conversations;
