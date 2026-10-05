-- Личный чат «Помощник»: владелец проекта скидывает сюда правки и скриншоты,
-- а Claude Code в сессии забирает их и отвечает.
--
-- Это не обычная переписка: ни шифрования, ни собеседников. Видит и пишет
-- только один аккаунт — тот, что записан в assistant_owner. Ответы Помощника
-- пишутся с серверной стороны (из сессии, под ролью postgres), поэтому
-- вставить сообщение «от Помощника» с телефона нельзя.

-- ── владелец ────────────────────────────────────────────────────────────────

create table assistant_owner (
  only_row   boolean primary key default true check (only_row),
  profile_id uuid not null references profiles on delete cascade
);
alter table assistant_owner enable row level security;
revoke all on assistant_owner from public, anon, authenticated;

-- ── сообщения ───────────────────────────────────────────────────────────────

create table assistant_messages (
  id              uuid primary key default gen_random_uuid(),
  from_user       boolean not null,
  body            text check (char_length(body) <= 4000),
  attachment_path text,
  created_at      timestamptz not null default now(),
  -- Когда Помощник забрал сообщение в работу; null — ещё не видел.
  handled_at      timestamptz,
  check (body is not null or attachment_path is not null)
);
create index assistant_messages_created_idx on assistant_messages (created_at);
create index assistant_messages_open_idx on assistant_messages (created_at)
  where from_user and handled_at is null;

alter table assistant_messages enable row level security;
revoke all on assistant_messages from public, anon, authenticated;

create function is_assistant_owner() returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select exists (select 1 from assistant_owner where profile_id = auth.uid());
$$;
revoke all on function is_assistant_owner() from public, anon;
grant execute on function is_assistant_owner() to authenticated;

grant select, insert on assistant_messages to authenticated;

create policy "помощник: читает владелец" on assistant_messages
  for select to authenticated
  using (is_assistant_owner());

create policy "помощник: пишет владелец, только от себя" on assistant_messages
  for insert to authenticated
  with check (
    is_assistant_owner()
    and from_user
    and handled_at is null
    and (attachment_path is null or attachment_path like auth.uid()::text || '/%')
  );

alter publication supabase_realtime add table assistant_messages;

-- ── вложения (скриншоты) ────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit)
values ('assistant', 'assistant', false, 26214400)
on conflict (id) do nothing;

create policy "assistant: владелец читает свои файлы" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'assistant'
    and is_assistant_owner()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "assistant: владелец грузит в свою папку" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'assistant'
    and is_assistant_owner()
    and (storage.foldername(name))[1] = auth.uid()::text
  );
