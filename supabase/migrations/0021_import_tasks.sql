-- Пакетное создание задач из JSON-файла (импорт на странице «Задачи»).
--
-- Разбор файла и подбор исполнителя по имени/email делает клиент, сюда приходит
-- уже нормализованный массив. Функция всё перепроверяет и создаёт задачи одной
-- транзакцией: либо все, либо ни одной. Триггеры ws_tasks (номер, журнал,
-- уведомления исполнителям) отрабатывают как при обычном создании.
--
-- Формат элемента: {title, description?, status?, priority?, assignee_id?, due_date?, labels?[]}
-- Зависит от 0017 и 0019 (номера задач).

create function ws_import_tasks(p_project uuid, p_tasks jsonb) returns jsonb
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  pr ws_projects;
  t jsonb;
  i int := 0;
  v_title text;
  v_status text;
  v_priority text;
  v_assignee uuid;
  v_due date;
  v_id uuid;
  v_num int;
  v_label text;
  v_label_id uuid;
  v_out jsonb := '[]'::jsonb;
begin
  select * into pr from ws_projects where id = p_project;
  if pr.id is null or not ws_is_admin(pr.workspace_id) then
    raise exception 'импортировать задачи могут только owner и admin';
  end if;
  if jsonb_typeof(p_tasks) <> 'array' then raise exception 'ожидался массив задач'; end if;
  if jsonb_array_length(p_tasks) = 0 then raise exception 'в файле нет задач'; end if;
  if jsonb_array_length(p_tasks) > 200 then raise exception 'не больше 200 задач за раз'; end if;

  for t in select * from jsonb_array_elements(p_tasks) loop
    i := i + 1;
    v_title := trim(coalesce(t ->> 'title', ''));
    if v_title = '' then raise exception 'задача %: нет названия', i; end if;
    if length(v_title) > 200 then raise exception 'задача %: название длиннее 200 символов', i; end if;

    v_status := coalesce(nullif(t ->> 'status', ''), 'todo');
    if v_status not in ('backlog', 'todo', 'in_progress', 'review', 'blocked', 'done') then
      raise exception 'задача %: неизвестный статус «%»', i, v_status;
    end if;
    v_priority := coalesce(nullif(t ->> 'priority', ''), 'medium');
    if v_priority not in ('low', 'medium', 'high', 'critical') then
      raise exception 'задача %: неизвестный приоритет «%»', i, v_priority;
    end if;

    v_assignee := null;
    if nullif(t ->> 'assignee_id', '') is not null then
      begin v_assignee := (t ->> 'assignee_id')::uuid;
      exception when others then raise exception 'задача %: некорректный исполнитель', i; end;
      if not exists (select 1 from ws_members m
                     where m.workspace_id = pr.workspace_id and m.user_id = v_assignee and m.status = 'active') then
        raise exception 'задача %: исполнитель не состоит в команде', i;
      end if;
    end if;

    v_due := null;
    if nullif(t ->> 'due_date', '') is not null then
      begin v_due := (t ->> 'due_date')::date;
      exception when others then raise exception 'задача %: некорректная дата «%»', i, t ->> 'due_date'; end;
    end if;

    insert into ws_tasks (workspace_id, project_id, title, description, status, priority, assignee_id, due_date)
    values (pr.workspace_id, pr.id, v_title, coalesce(t ->> 'description', ''), v_status, v_priority, v_assignee, v_due)
    returning id, num into v_id, v_num;

    if jsonb_typeof(t -> 'labels') = 'array' then
      for v_label in select trim(x) from jsonb_array_elements_text(t -> 'labels') x loop
        continue when v_label = '' or length(v_label) > 40;
        select id into v_label_id from ws_labels
        where workspace_id = pr.workspace_id and lower(name) = lower(v_label);
        if v_label_id is null then
          insert into ws_labels (workspace_id, name) values (pr.workspace_id, v_label) returning id into v_label_id;
        end if;
        insert into ws_task_labels (task_id, label_id) values (v_id, v_label_id) on conflict do nothing;
      end loop;
    end if;

    v_out := v_out || jsonb_build_object('id', v_id, 'num', v_num, 'title', v_title);
  end loop;

  return v_out;
end
$$;

grant execute on function ws_import_tasks to authenticated;
