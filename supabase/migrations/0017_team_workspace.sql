-- Внутренний Team Workspace (dashboard команды на сайте social-world).
--
-- Не зависит от 0015/0016, трогает только auth.users. Все таблицы с префиксом
-- ws_ в схеме public: отдельная схема потребовала бы менять PGRST_DB_SCHEMAS на
-- боевом сервере, а префикс не пересекается с таблицами приложения.
--
-- ВАЖНО: auth.users общие с пользователями приложения. Сам факт входа ничего
-- не даёт — доступ определяет строка в ws_members (status = 'active').
--
-- Иерархия: workspace → project → tasks / conversations / activity.
-- Файлы — приватный бакет ws-files, доступ по членству в workspace.

-- ── каркас ──────────────────────────────────────────────────────────────────

create table ws_workspaces (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  created_at  timestamptz not null default now()
);

create table ws_projects (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  name          text not null,
  slug          text not null,
  created_at    timestamptz not null default now(),
  archived_at   timestamptz,
  unique (workspace_id, slug),
  unique (id, workspace_id)
);

create table ws_members (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  -- null, пока приглашённый не принял приглашение
  user_id       uuid references auth.users(id) on delete set null,
  email         text not null,
  name          text not null check (length(trim(name)) > 0),
  avatar_url    text,
  role          text not null default 'member' check (role in ('owner', 'admin', 'member')),
  -- pending зарезервирован под ручное одобрение; сейчас приглашение
  -- принимается по токену сразу в active
  status        text not null default 'invited'
                check (status in ('active', 'invited', 'pending', 'suspended')),
  invited_by    uuid references auth.users(id) on delete set null,
  joined_at     timestamptz,
  last_seen     timestamptz,
  created_at    timestamptz not null default now(),
  unique (workspace_id, user_id)
);
create unique index ws_members_email_uq on ws_members (workspace_id, lower(email));
create index ws_members_user_idx on ws_members (user_id);

create table ws_invitations (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  member_id     uuid not null references ws_members(id) on delete cascade,
  email         text not null,
  role          text not null check (role in ('admin', 'member')),
  message       text,
  -- сам токен нигде не хранится, только sha256; показывается один раз при создании
  token_hash    bytea not null unique,
  status        text not null default 'invited'
                check (status in ('invited', 'accepted', 'revoked', 'expired')),
  invited_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '14 days',
  accepted_at   timestamptz
);

-- ── проверки доступа ────────────────────────────────────────────────────────

create function ws_role(p_ws uuid) returns text
language sql stable security definer
set search_path = public
set row_security = off
as $$
  select role from ws_members
  where workspace_id = p_ws and user_id = auth.uid() and status = 'active'
$$;

create function ws_is_member(p_ws uuid) returns boolean
language sql stable security definer
set search_path = public
set row_security = off
as $$ select ws_role(p_ws) is not null $$;

create function ws_is_admin(p_ws uuid) returns boolean
language sql stable security definer
set search_path = public
set row_security = off
as $$ select coalesce(ws_role(p_ws) in ('owner', 'admin'), false) $$;

-- ── задачи ──────────────────────────────────────────────────────────────────

create table ws_tasks (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null,
  project_id    uuid not null,
  title         text not null check (length(trim(title)) > 0),
  description   text not null default '',
  status        text not null default 'todo'
                check (status in ('backlog', 'todo', 'in_progress', 'review', 'blocked', 'done')),
  priority      text not null default 'medium'
                check (priority in ('low', 'medium', 'high', 'critical')),
  assignee_id   uuid references auth.users(id) on delete set null,
  creator_id    uuid references auth.users(id) on delete set null default auth.uid(),
  due_date      date,
  -- порядок внутри колонки; при перетаскивании берётся среднее соседей
  position      double precision not null default (extract(epoch from clock_timestamp()) * 1000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  completed_at  timestamptz,
  archived_at   timestamptz,
  foreign key (project_id, workspace_id) references ws_projects(id, workspace_id) on delete cascade
);
create index ws_tasks_project_idx on ws_tasks (project_id, status, position) where archived_at is null;
create index ws_tasks_assignee_idx on ws_tasks (assignee_id) where archived_at is null;
create index ws_tasks_due_idx on ws_tasks (due_date) where archived_at is null and status <> 'done';

create function ws_task_ws(p_task uuid) returns uuid
language sql stable security definer
set search_path = public
set row_security = off
as $$ select workspace_id from ws_tasks where id = p_task $$;

create table ws_labels (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  name          text not null check (length(trim(name)) > 0),
  color         text not null default '#c4677c'
);
create unique index ws_labels_name_uq on ws_labels (workspace_id, lower(name));

create table ws_task_labels (
  task_id   uuid not null references ws_tasks(id) on delete cascade,
  label_id  uuid not null references ws_labels(id) on delete cascade,
  primary key (task_id, label_id)
);

create table ws_task_watchers (
  task_id  uuid not null references ws_tasks(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  primary key (task_id, user_id)
);

-- ── комментарии ─────────────────────────────────────────────────────────────

create table ws_comments (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null,
  task_id       uuid not null references ws_tasks(id) on delete cascade,
  parent_id     uuid references ws_comments(id) on delete cascade,
  author_id     uuid references auth.users(id) on delete set null default auth.uid(),
  body          text not null check (length(trim(body)) > 0),
  -- id участников, упомянутых через @; уведомления шлёт триггер
  mentions      uuid[] not null default '{}',
  created_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz
);
create index ws_comments_task_idx on ws_comments (task_id, created_at);

-- ── чат ─────────────────────────────────────────────────────────────────────

create table ws_conversations (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  project_id    uuid references ws_projects(id) on delete cascade,
  kind          text not null check (kind in ('channel', 'direct')),
  name          text,
  -- для direct: два отсортированных uuid через ':' — не даёт завести дубль диалога
  direct_key    text unique,
  created_at    timestamptz not null default now()
);

create table ws_conversation_members (
  conversation_id  uuid not null references ws_conversations(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  last_read_at     timestamptz,
  primary key (conversation_id, user_id)
);

create table ws_messages (
  id               uuid primary key default gen_random_uuid(),
  workspace_id     uuid not null,
  conversation_id  uuid not null references ws_conversations(id) on delete cascade,
  author_id        uuid references auth.users(id) on delete set null default auth.uid(),
  body             text not null check (length(trim(body)) > 0),
  created_at       timestamptz not null default now(),
  edited_at        timestamptz,
  deleted_at       timestamptz
);
create index ws_messages_conv_idx on ws_messages (conversation_id, created_at desc);

create function ws_can_read_conv(p_conv uuid) returns boolean
language sql stable security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from ws_conversations c
    where c.id = p_conv
      and (
        (c.kind = 'channel' and ws_is_member(c.workspace_id))
        or exists (
          select 1 from ws_conversation_members m
          where m.conversation_id = c.id and m.user_id = auth.uid()
        ) and ws_is_member(c.workspace_id)
      )
  )
$$;

-- ── файлы ───────────────────────────────────────────────────────────────────

create table ws_attachments (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null,
  task_id       uuid references ws_tasks(id) on delete cascade,
  message_id    uuid references ws_messages(id) on delete cascade,
  -- <workspace_id>/<uploader_id>/<uuid>-<имя файла> в бакете ws-files
  storage_path  text not null unique,
  filename      text not null,
  mime          text,
  size          bigint not null check (size >= 0),
  uploader_id   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  check (num_nonnulls(task_id, message_id) = 1)
);
create index ws_attachments_task_idx on ws_attachments (task_id);
create index ws_attachments_ws_idx on ws_attachments (workspace_id, created_at desc);

-- ── уведомления и журнал ────────────────────────────────────────────────────

create table ws_notifications (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  actor_id      uuid references auth.users(id) on delete set null,
  kind          text not null check (kind in
                  ('assigned', 'updated', 'mention', 'comment', 'status', 'blocked',
                   'overdue', 'invite', 'file')),
  title         text not null,
  -- путь внутри dashboard, например /tasks/<id>
  link          text not null,
  dedupe        text,
  read_at       timestamptz,
  created_at    timestamptz not null default now(),
  unique (user_id, dedupe)
);
create index ws_notifications_user_idx on ws_notifications (user_id, created_at desc);

create table ws_activity (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references ws_workspaces(id) on delete cascade,
  project_id    uuid references ws_projects(id) on delete cascade,
  actor_id      uuid references auth.users(id) on delete set null,
  entity_type   text not null,
  entity_id     uuid,
  action        text not null,
  -- {title, from, to, filename ...}: интерфейс собирает из этого текст
  meta          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index ws_activity_ws_idx on ws_activity (workspace_id, created_at desc);
create index ws_activity_entity_idx on ws_activity (entity_id, created_at desc);

-- ── внутренние помощники (клиенту не выдаются) ──────────────────────────────

create function ws_log(
  p_ws uuid, p_project uuid, p_type text, p_entity uuid, p_action text, p_meta jsonb
) returns void
language sql security definer
set search_path = public
set row_security = off
as $$
  insert into ws_activity (workspace_id, project_id, actor_id, entity_type, entity_id, action, meta)
  values (p_ws, p_project, auth.uid(), p_type, p_entity, p_action, coalesce(p_meta, '{}'::jsonb))
$$;

create function ws_notify(
  p_ws uuid, p_user uuid, p_kind text, p_title text, p_link text, p_dedupe text default null
) returns void
language sql security definer
set search_path = public
set row_security = off
as $$
  insert into ws_notifications (workspace_id, user_id, actor_id, kind, title, link, dedupe)
  select p_ws, p_user, auth.uid(), p_kind, p_title, p_link, p_dedupe
  where p_user is not null
    and p_user is distinct from auth.uid()
    and exists (select 1 from ws_members m
                where m.workspace_id = p_ws and m.user_id = p_user and m.status = 'active')
  on conflict (user_id, dedupe) do nothing
$$;

create function ws_notify_watchers(
  p_task uuid, p_kind text, p_title text, p_skip uuid default null
) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  t ws_tasks;
  w uuid;
begin
  select * into t from ws_tasks where id = p_task;
  for w in select user_id from ws_task_watchers where task_id = p_task loop
    if w is distinct from p_skip then
      perform ws_notify(t.workspace_id, w, p_kind, p_title, '/tasks/' || t.id);
    end if;
  end loop;
end
$$;

revoke all on function ws_log, ws_notify, ws_notify_watchers from public, anon, authenticated;

-- ── триггеры задач ──────────────────────────────────────────────────────────

create function ws_tasks_before() returns trigger
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
  if auth.uid() is not null and not ws_is_admin(old.workspace_id) then
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
create trigger ws_tasks_before before insert or update on ws_tasks
  for each row execute function ws_tasks_before();

create function ws_tasks_after() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  link text := '/tasks/' || new.id;
  ttl text := new.title;
begin
  if tg_op = 'INSERT' then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id, 'task.created',
                   jsonb_build_object('title', ttl));
    insert into ws_task_watchers (task_id, user_id)
    select new.id, u from unnest(array[new.creator_id, new.assignee_id]) u
    where u is not null on conflict do nothing;
    perform ws_notify(new.workspace_id, new.assignee_id, 'assigned',
                      'Вам назначили задачу «' || ttl || '»', link);
    return new;
  end if;

  if new.status is distinct from old.status then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id, 'task.status',
                   jsonb_build_object('title', ttl, 'from', old.status, 'to', new.status));
    if new.status = 'blocked' then
      perform ws_notify_watchers(new.id, 'blocked', 'Задача «' || ttl || '» заблокирована', auth.uid());
    else
      perform ws_notify_watchers(new.id, 'status', 'Статус «' || ttl || '» изменён', auth.uid());
    end if;
  end if;

  if new.assignee_id is distinct from old.assignee_id then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id, 'task.assigned',
                   jsonb_build_object('title', ttl, 'from', old.assignee_id, 'to', new.assignee_id));
    if new.assignee_id is not null then
      insert into ws_task_watchers (task_id, user_id) values (new.id, new.assignee_id)
      on conflict do nothing;
      perform ws_notify(new.workspace_id, new.assignee_id, 'assigned',
                        'Вам назначили задачу «' || ttl || '»', link);
    end if;
  end if;

  if new.priority is distinct from old.priority then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id, 'task.priority',
                   jsonb_build_object('title', ttl, 'from', old.priority, 'to', new.priority));
    perform ws_notify_watchers(new.id, 'updated', 'Приоритет «' || ttl || '» изменён', auth.uid());
  end if;

  if new.due_date is distinct from old.due_date then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id, 'task.due',
                   jsonb_build_object('title', ttl, 'from', old.due_date, 'to', new.due_date));
    perform ws_notify_watchers(new.id, 'updated', 'Срок «' || ttl || '» изменён', auth.uid());
  end if;

  if new.title is distinct from old.title or new.description is distinct from old.description then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id, 'task.edited',
                   jsonb_build_object('title', ttl));
  end if;

  if new.archived_at is distinct from old.archived_at then
    perform ws_log(new.workspace_id, new.project_id, 'task', new.id,
                   case when new.archived_at is null then 'task.restored' else 'task.archived' end,
                   jsonb_build_object('title', ttl));
  end if;
  return new;
end
$$;
create trigger ws_tasks_after after insert or update on ws_tasks
  for each row execute function ws_tasks_after();

-- ── триггеры комментариев, файлов, сообщений ───────────────────────────────

create function ws_comments_before() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if tg_op = 'INSERT' then
    new.workspace_id := ws_task_ws(new.task_id);
    if new.workspace_id is null then raise exception 'задача не найдена'; end if;
    if auth.uid() is not null then new.author_id := auth.uid(); end if;
    if new.parent_id is not null and not exists (
      select 1 from ws_comments p where p.id = new.parent_id and p.task_id = new.task_id
    ) then raise exception 'родительский комментарий из другой задачи'; end if;
  else
    if new.task_id <> old.task_id or new.author_id is distinct from old.author_id
       or new.parent_id is distinct from old.parent_id then
      raise exception 'привязку комментария менять нельзя';
    end if;
    if new.body is distinct from old.body and new.deleted_at is null then
      new.edited_at := now();
    end if;
  end if;
  return new;
end
$$;
create trigger ws_comments_before before insert or update on ws_comments
  for each row execute function ws_comments_before();

create function ws_comments_after() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  t ws_tasks;
  m uuid;
begin
  select * into t from ws_tasks where id = new.task_id;
  perform ws_log(t.workspace_id, t.project_id, 'task', t.id, 'comment.created',
                 jsonb_build_object('title', t.title));
  insert into ws_task_watchers (task_id, user_id) values (t.id, new.author_id)
    on conflict do nothing;
  foreach m in array new.mentions loop
    perform ws_notify(t.workspace_id, m, 'mention',
                      'Вас упомянули в «' || t.title || '»', '/tasks/' || t.id);
  end loop;
  perform ws_notify_watchers(t.id, 'comment', 'Новый комментарий в «' || t.title || '»',
                             new.author_id);
  return new;
end
$$;
create trigger ws_comments_after after insert on ws_comments
  for each row execute function ws_comments_after();

create function ws_messages_before() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if tg_op = 'INSERT' then
    select workspace_id into new.workspace_id from ws_conversations where id = new.conversation_id;
    if auth.uid() is not null then new.author_id := auth.uid(); end if;
  else
    if new.conversation_id <> old.conversation_id or new.author_id is distinct from old.author_id then
      raise exception 'привязку сообщения менять нельзя';
    end if;
    if new.body is distinct from old.body and new.deleted_at is null then
      new.edited_at := now();
    end if;
  end if;
  return new;
end
$$;
create trigger ws_messages_before before insert or update on ws_messages
  for each row execute function ws_messages_before();

create function ws_attachments_before() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  new.workspace_id := coalesce(
    ws_task_ws(new.task_id),
    (select workspace_id from ws_messages where id = new.message_id)
  );
  if new.workspace_id is null then raise exception 'к чему привязан файл — не найдено'; end if;
  if auth.uid() is not null then new.uploader_id := auth.uid(); end if;
  if split_part(new.storage_path, '/', 1) <> new.workspace_id::text then
    raise exception 'путь файла должен начинаться с id workspace';
  end if;
  return new;
end
$$;
create trigger ws_attachments_before before insert on ws_attachments
  for each row execute function ws_attachments_before();

create function ws_attachments_after() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare t ws_tasks;
begin
  if new.task_id is null then return new; end if;
  select * into t from ws_tasks where id = new.task_id;
  perform ws_log(t.workspace_id, t.project_id, 'task', t.id, 'file.uploaded',
                 jsonb_build_object('title', t.title, 'filename', new.filename));
  perform ws_notify_watchers(t.id, 'file', 'Новый файл в «' || t.title || '»', new.uploader_id);
  return new;
end
$$;
create trigger ws_attachments_after after insert on ws_attachments
  for each row execute function ws_attachments_after();

-- ── защита ws_members ───────────────────────────────────────────────────────

create function ws_members_guard() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is null then return new; end if;  -- сервисный доступ
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
create trigger ws_members_guard before update on ws_members
  for each row execute function ws_members_guard();

-- ── RPC ─────────────────────────────────────────────────────────────────────

-- Приглашение. Возвращает токен: он показывается один раз, в базе только sha256.
-- Письмо не отправляется — токен админ передаёт человеку сам (ссылкой).
create function ws_invite_member(
  p_ws uuid, p_name text, p_email text, p_role text, p_message text default null
) returns text
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  v_member ws_members;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not ws_is_admin(p_ws) then raise exception 'приглашать могут owner и admin'; end if;
  if p_role not in ('admin', 'member') then raise exception 'роль: admin или member'; end if;
  if p_role = 'admin' and ws_role(p_ws) <> 'owner' then
    raise exception 'администраторов приглашает только owner';
  end if;
  if position('@' in p_email) < 2 then raise exception 'некорректный email'; end if;
  if exists (select 1 from ws_members where workspace_id = p_ws and lower(email) = lower(p_email)) then
    raise exception 'участник с таким email уже есть';
  end if;

  insert into ws_members (workspace_id, email, name, role, status, invited_by)
  values (p_ws, trim(p_email), trim(p_name), p_role, 'invited', auth.uid())
  returning * into v_member;

  insert into ws_invitations (workspace_id, member_id, email, role, message, token_hash, invited_by)
  values (p_ws, v_member.id, v_member.email, p_role, nullif(trim(p_message), ''),
          sha256(convert_to(v_token, 'utf8')), auth.uid());

  perform ws_log(p_ws, null, 'member', v_member.id, 'member.invited',
                 jsonb_build_object('name', v_member.name, 'role', p_role));
  return v_token;
end
$$;

-- Новый токен для уже приглашённого (старый погашается).
create function ws_reissue_invitation(p_member uuid) returns text
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  m ws_members;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  select * into m from ws_members where id = p_member;
  if m.id is null or not ws_is_admin(m.workspace_id) then raise exception 'нет доступа'; end if;
  if m.status <> 'invited' then raise exception 'участник уже принял приглашение'; end if;
  update ws_invitations set status = 'revoked' where member_id = m.id and status = 'invited';
  insert into ws_invitations (workspace_id, member_id, email, role, token_hash, invited_by)
  values (m.workspace_id, m.id, m.email, m.role, sha256(convert_to(v_token, 'utf8')), auth.uid());
  return v_token;
end
$$;

-- Что за приглашение — для экрана принятия (вызывается до входа).
create function ws_invitation_preview(p_token text) returns table (
  workspace_name text, name text, email text, role text, message text
)
language sql stable security definer
set search_path = public
set row_security = off
as $$
  select w.name, m.name, i.email, i.role, i.message
  from ws_invitations i
  join ws_workspaces w on w.id = i.workspace_id
  join ws_members m on m.id = i.member_id
  where i.token_hash = sha256(convert_to(p_token, 'utf8'))
    and i.status = 'invited' and i.expires_at > now()
$$;

-- Принять приглашение: вошедший пользователь должен иметь тот же email.
create function ws_accept_invitation(p_token text) returns uuid
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  i ws_invitations;
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then raise exception 'нужно войти'; end if;
  select * into i from ws_invitations
  where token_hash = sha256(convert_to(p_token, 'utf8')) for update;
  if i.id is null or i.status <> 'invited' or i.expires_at <= now() then
    raise exception 'приглашение недействительно или просрочено';
  end if;
  if lower(i.email) <> v_email then
    raise exception 'приглашение выписано на другой email';
  end if;
  if exists (select 1 from ws_members where workspace_id = i.workspace_id and user_id = auth.uid()) then
    raise exception 'вы уже участник этого workspace';
  end if;

  update ws_members
     set user_id = auth.uid(), status = 'active', joined_at = now(), last_seen = now()
   where id = i.member_id;
  update ws_invitations set status = 'accepted', accepted_at = now() where id = i.id;

  perform ws_log(i.workspace_id, null, 'member', i.member_id, 'member.joined',
                 jsonb_build_object('name', (select name from ws_members where id = i.member_id)));
  return i.workspace_id;
end
$$;

-- Первые владельцы. Вызывается вручную из psql под postgres, клиенту недоступно.
-- Пользователь должен уже существовать в auth.users.
create function ws_bootstrap_owner(p_ws uuid, p_email text, p_name text) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare v_user uuid;
begin
  select id into v_user from auth.users where lower(email) = lower(p_email);
  if v_user is null then raise exception 'в auth.users нет %', p_email; end if;
  insert into ws_members (workspace_id, user_id, email, name, role, status, joined_at)
  values (p_ws, v_user, p_email, p_name, 'owner', 'active', now())
  on conflict (workspace_id, user_id) do update set role = 'owner', status = 'active';
end
$$;
revoke all on function ws_bootstrap_owner from public, anon, authenticated;

-- Присутствие (last_seen); реже раза в минуту не пишет.
create function ws_touch(p_ws uuid) returns void
language sql security definer
set search_path = public
set row_security = off
as $$
  update ws_members set last_seen = now()
  where workspace_id = p_ws and user_id = auth.uid() and status = 'active'
    and (last_seen is null or last_seen < now() - interval '1 minute')
$$;

-- Личный диалог; повторный вызов возвращает существующий.
create function ws_open_direct(p_ws uuid, p_other uuid) returns uuid
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  v_key text;
  v_id uuid;
begin
  if not ws_is_member(p_ws) then raise exception 'нет доступа'; end if;
  if p_other = auth.uid() then raise exception 'нельзя написать самому себе'; end if;
  if not exists (select 1 from ws_members where workspace_id = p_ws and user_id = p_other and status = 'active') then
    raise exception 'адресат не участник workspace';
  end if;
  v_key := least(auth.uid()::text, p_other::text) || ':' || greatest(auth.uid()::text, p_other::text);
  select id into v_id from ws_conversations where direct_key = v_key;
  if v_id is null then
    insert into ws_conversations (workspace_id, kind, direct_key) values (p_ws, 'direct', v_key)
    returning id into v_id;
    insert into ws_conversation_members (conversation_id, user_id) values (v_id, auth.uid()), (v_id, p_other);
  end if;
  return v_id;
end
$$;

-- Отметить диалог прочитанным (для канала строка создаётся при первом вызове).
create function ws_mark_read(p_conv uuid) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if not ws_can_read_conv(p_conv) then raise exception 'нет доступа'; end if;
  insert into ws_conversation_members (conversation_id, user_id, last_read_at)
  values (p_conv, auth.uid(), now())
  on conflict (conversation_id, user_id) do update set last_read_at = now();
end
$$;

create function ws_unread_counts(p_ws uuid) returns table (conversation_id uuid, unread bigint)
language sql stable security definer
set search_path = public
set row_security = off
as $$
  select c.id, count(msg.id)
  from ws_conversations c
  left join ws_conversation_members cm
         on cm.conversation_id = c.id and cm.user_id = auth.uid()
  left join ws_messages msg
         on msg.conversation_id = c.id
        and msg.deleted_at is null
        and msg.author_id is distinct from auth.uid()
        and msg.created_at > coalesce(cm.last_read_at, '-infinity')
  where c.workspace_id = p_ws and ws_can_read_conv(c.id)
  group by c.id
$$;

-- Просроченные задачи → уведомления исполнителю (по разу на пару задача+срок).
-- Планировщика (pg_cron) на сервере нет, поэтому вызывается при открытии dashboard.
create function ws_sync_overdue(p_ws uuid) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare t record;
begin
  if not ws_is_member(p_ws) then return; end if;
  for t in
    select id, title, assignee_id, due_date from ws_tasks
    where workspace_id = p_ws and archived_at is null and status <> 'done'
      and due_date < current_date and assignee_id is not null
  loop
    insert into ws_notifications (workspace_id, user_id, kind, title, link, dedupe)
    values (p_ws, t.assignee_id, 'overdue', 'Задача «' || t.title || '» просрочена',
            '/tasks/' || t.id, 'overdue:' || t.id || ':' || t.due_date)
    on conflict (user_id, dedupe) do nothing;
  end loop;
end
$$;

-- Сводка для главной: счётчики по статусам и просрочка одним запросом.
create function ws_project_stats(p_project uuid) returns jsonb
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
  from ws_tasks where project_id = p_project and archived_at is null
$$;

-- Глобальный поиск; работает от имени вызывающего, поэтому RLS отсекает чужое.
create function ws_search(p_ws uuid, p_q text) returns jsonb
language plpgsql stable
as $$
declare
  v_like text := '%' || replace(replace(replace(trim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  if length(trim(p_q)) < 2 then
    return jsonb_build_object('tasks', '[]'::jsonb, 'members', '[]'::jsonb,
                              'messages', '[]'::jsonb, 'files', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'tasks', coalesce((select jsonb_agg(x) from (
      select id, title, status from ws_tasks
      where workspace_id = p_ws and archived_at is null
        and (title ilike v_like or description ilike v_like)
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

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table ws_workspaces          enable row level security;
alter table ws_projects            enable row level security;
alter table ws_members             enable row level security;
alter table ws_invitations         enable row level security;
alter table ws_tasks               enable row level security;
alter table ws_labels              enable row level security;
alter table ws_task_labels         enable row level security;
alter table ws_task_watchers       enable row level security;
alter table ws_comments            enable row level security;
alter table ws_conversations       enable row level security;
alter table ws_conversation_members enable row level security;
alter table ws_messages            enable row level security;
alter table ws_attachments         enable row level security;
alter table ws_notifications       enable row level security;
alter table ws_activity            enable row level security;

create policy "workspace видят участники" on ws_workspaces
  for select to authenticated using (ws_is_member(id));

create policy "проекты видят участники" on ws_projects
  for select to authenticated using (ws_is_member(workspace_id));

create policy "участников видят участники" on ws_members
  for select to authenticated using (ws_is_member(workspace_id));
create policy "админы меняют роль и статус" on ws_members
  for update to authenticated using (ws_is_admin(workspace_id)) with check (ws_is_admin(workspace_id));
create policy "админы удаляют неприянятые приглашения" on ws_members
  for delete to authenticated using (ws_is_admin(workspace_id) and status = 'invited');

create policy "приглашения видят админы" on ws_invitations
  for select to authenticated using (ws_is_admin(workspace_id));

create policy "задачи видят участники" on ws_tasks
  for select to authenticated using (ws_is_member(workspace_id));
create policy "задачи создают админы" on ws_tasks
  for insert to authenticated with check (ws_is_admin(workspace_id));
create policy "задачи правят участники (поля режет триггер)" on ws_tasks
  for update to authenticated using (ws_is_member(workspace_id)) with check (ws_is_member(workspace_id));
create policy "задачи удаляют админы" on ws_tasks
  for delete to authenticated using (ws_is_admin(workspace_id));

create policy "метки видят участники" on ws_labels
  for select to authenticated using (ws_is_member(workspace_id));
create policy "метки ведут админы" on ws_labels
  for all to authenticated using (ws_is_admin(workspace_id)) with check (ws_is_admin(workspace_id));

create policy "метки задач видят участники" on ws_task_labels
  for select to authenticated using (ws_is_member(ws_task_ws(task_id)));
create policy "метки задач ставят админы" on ws_task_labels
  for all to authenticated
  using (ws_is_admin(ws_task_ws(task_id)))
  with check (ws_is_admin(ws_task_ws(task_id)));

create policy "наблюдателей видят участники" on ws_task_watchers
  for select to authenticated using (ws_is_member(ws_task_ws(task_id)));
create policy "наблюдателей ставит сам участник или админ" on ws_task_watchers
  for all to authenticated
  using (ws_is_member(ws_task_ws(task_id)) and (user_id = auth.uid() or ws_is_admin(ws_task_ws(task_id))))
  with check (ws_is_member(ws_task_ws(task_id)) and (user_id = auth.uid() or ws_is_admin(ws_task_ws(task_id))));

create policy "комментарии видят участники" on ws_comments
  for select to authenticated using (ws_is_member(workspace_id));
create policy "комментировать может любой участник" on ws_comments
  for insert to authenticated with check (ws_is_member(ws_task_ws(task_id)) and author_id = auth.uid());
create policy "свои комментарии правит автор" on ws_comments
  for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy "диалоги видят участники" on ws_conversations
  for select to authenticated using (ws_can_read_conv(id));
create policy "членство в диалоге — своё" on ws_conversation_members
  for select to authenticated using (user_id = auth.uid());

create policy "сообщения читают участники диалога" on ws_messages
  for select to authenticated using (ws_can_read_conv(conversation_id));
create policy "писать может участник диалога" on ws_messages
  for insert to authenticated with check (ws_can_read_conv(conversation_id) and author_id = auth.uid());
create policy "свои сообщения правит автор" on ws_messages
  for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy "файлы видят участники" on ws_attachments
  for select to authenticated using (ws_is_member(workspace_id));
create policy "файл добавляет участник" on ws_attachments
  for insert to authenticated with check (
    uploader_id = auth.uid()
    and (
      (task_id is not null and ws_is_member(ws_task_ws(task_id)))
      or (message_id is not null and exists (
            select 1 from ws_messages m where m.id = message_id and ws_can_read_conv(m.conversation_id)))
    )
  );
create policy "файл удаляет загрузивший или админ" on ws_attachments
  for delete to authenticated using (uploader_id = auth.uid() or ws_is_admin(workspace_id));

create policy "уведомления — свои" on ws_notifications
  for select to authenticated using (user_id = auth.uid());
create policy "прочитать можно только своё" on ws_notifications
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "журнал видят участники" on ws_activity
  for select to authenticated using (ws_is_member(workspace_id));

-- ── гранты ──────────────────────────────────────────────────────────────────

-- Только ws_-таблицы: таблицы приложения не трогаем.
do $$
declare t text;
begin
  foreach t in array array['ws_workspaces','ws_projects','ws_members','ws_invitations','ws_tasks',
    'ws_labels','ws_task_labels','ws_task_watchers','ws_comments','ws_conversations',
    'ws_conversation_members','ws_messages','ws_attachments','ws_notifications','ws_activity']
  loop
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
end $$;

grant select on ws_workspaces, ws_projects, ws_invitations, ws_conversations,
                ws_conversation_members, ws_activity to authenticated;
grant select on ws_members to authenticated;
grant update (role, status) on ws_members to authenticated;
grant delete on ws_members to authenticated;
grant select, insert, update, delete on ws_tasks, ws_labels, ws_task_labels, ws_task_watchers to authenticated;
grant select, insert, update on ws_comments, ws_messages to authenticated;
grant select, insert, delete on ws_attachments to authenticated;
grant select on ws_notifications to authenticated;
grant update (read_at) on ws_notifications to authenticated;

grant execute on function
  ws_role, ws_is_member, ws_is_admin, ws_task_ws, ws_can_read_conv,
  ws_invite_member, ws_reissue_invitation, ws_accept_invitation, ws_touch,
  ws_open_direct, ws_mark_read, ws_unread_counts, ws_sync_overdue,
  ws_project_stats, ws_search
to authenticated;
grant execute on function ws_invitation_preview to anon, authenticated;

-- ── файлы ───────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit)
values ('ws-files', 'ws-files', false, 26214400)
on conflict (id) do nothing;

-- Путь: <workspace_id>/<user_id>/<uuid>-<имя>. Приведение к uuid безопасное:
-- чужие бакеты и мусорные пути дают null, а не ошибку.
create function ws_storage_ws(p_name text) returns uuid
language plpgsql immutable
as $$
begin
  return split_part(p_name, '/', 1)::uuid;
exception when others then
  return null;
end
$$;
grant execute on function ws_storage_ws to authenticated;

create policy "ws-files читают участники" on storage.objects
  for select to authenticated
  using (bucket_id = 'ws-files' and ws_is_member(ws_storage_ws(name)));

create policy "ws-files грузят участники в свою папку" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'ws-files'
    and ws_is_member(ws_storage_ws(name))
    and split_part(name, '/', 2) = auth.uid()::text
  );

create policy "ws-files удаляет автор или админ" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'ws-files'
    and (split_part(name, '/', 2) = auth.uid()::text or ws_is_admin(ws_storage_ws(name)))
  );

-- ── realtime ────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table ws_messages, ws_tasks, ws_comments, ws_notifications;

-- ── стартовые данные: один workspace, один проект, общий канал ──────────────
-- Владельцев добавляют вручную: select ws_bootstrap_owner(<ws id>, 'email', 'Имя');

with w as (
  insert into ws_workspaces (name, slug) values ('Social World', 'social-world') returning id
), p as (
  insert into ws_projects (workspace_id, name, slug)
  select id, 'Social World', 'social-world' from w returning id, workspace_id
)
insert into ws_conversations (workspace_id, project_id, kind, name)
select workspace_id, id, 'channel', 'Общий' from p;
