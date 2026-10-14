-- Тестировщики и раздел «Для багов».
--
-- Владелец проекта (assistant_owner) назначает тестировщиков прямо из профиля
-- человека. У тестировщика в «Моих разделах» появляется «Для багов» — такой же
-- чат, как «Помощник» у владельца (та же таблица assistant_messages, канал
-- 'bugs'): он пишет найденные баги и прикладывает скриншоты. Видит он только
-- свою переписку. Claude раз в сутки забирает баги, сводит их и отдаёт
-- владельцу (tools/assistant/bugs.ps1); ответы пишет с серверной стороны.

create table app_testers (
  profile_id uuid primary key references profiles on delete cascade,
  added_at   timestamptz not null default now()
);
alter table app_testers enable row level security;
revoke all on app_testers from public, anon, authenticated;

create function is_app_tester() returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select exists (select 1 from app_testers where profile_id = auth.uid());
$$;
revoke all on function is_app_tester() from public, anon;
grant execute on function is_app_tester() to authenticated;

-- Кем человек приходится проекту: владелец, тестировщик. Для меню.
create function my_app_roles() returns jsonb
language sql stable security definer set search_path = public set row_security = off as $$
  select jsonb_build_object(
    'owner', exists (select 1 from assistant_owner where profile_id = auth.uid()),
    'tester', exists (select 1 from app_testers where profile_id = auth.uid())
  );
$$;
revoke all on function my_app_roles() from public, anon;
grant execute on function my_app_roles() to authenticated;

-- Назначить или снять тестировщика: только владелец.
create function set_app_tester(in_profile uuid, in_on boolean) returns void
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  if not is_assistant_owner() then
    raise exception 'Только владелец проекта' using errcode = '42501';
  end if;
  if in_on then
    insert into app_testers (profile_id) values (in_profile) on conflict do nothing;
  else
    delete from app_testers where profile_id = in_profile;
  end if;
end;
$$;
revoke all on function set_app_tester(uuid, boolean) from public, anon;
grant execute on function set_app_tester(uuid, boolean) to authenticated;

-- Тестировщик ли этот человек — для пункта меню владельца в его профиле.
create function is_profile_tester(in_profile uuid) returns boolean
language sql stable security definer set search_path = public set row_security = off as $$
  select is_assistant_owner() and exists (select 1 from app_testers where profile_id = in_profile);
$$;
revoke all on function is_profile_tester(uuid) from public, anon;
grant execute on function is_profile_tester(uuid) to authenticated;

-- ── сообщения: канал и автор ────────────────────────────────────────────────

alter table assistant_messages
  add column channel text not null default 'assistant' check (channel in ('assistant', 'bugs')),
  -- Чья это ветка: тестировщик (его сообщения и ответы ему). У «Помощника» —
  -- null, он один на владельца.
  add column author_id uuid references profiles on delete cascade;

create index assistant_messages_bugs_idx on assistant_messages (author_id, created_at) where channel = 'bugs';

-- Прежние политики касались только владельца и не знали о каналах.
drop policy "помощник: читает владелец" on assistant_messages;
drop policy "помощник: пишет владелец, только от себя" on assistant_messages;
drop policy "помощник: владелец правит ждущее" on assistant_messages;
drop policy "помощник: владелец удаляет ждущее" on assistant_messages;

create policy "помощник: читает владелец" on assistant_messages
  for select to authenticated
  using (channel = 'assistant' and is_assistant_owner());

create policy "баги: тестировщик читает свою ветку" on assistant_messages
  for select to authenticated
  using (channel = 'bugs' and author_id = auth.uid() and is_app_tester());

create policy "помощник: пишет владелец, только от себя" on assistant_messages
  for insert to authenticated
  with check (
    channel = 'assistant'
    and author_id is null
    and is_assistant_owner()
    and from_user
    and handled_at is null
    and (attachment_path is null or attachment_path like auth.uid()::text || '/%')
  );

create policy "баги: тестировщик пишет в свою ветку" on assistant_messages
  for insert to authenticated
  with check (
    channel = 'bugs'
    and author_id = auth.uid()
    and is_app_tester()
    and from_user
    and handled_at is null
    and (attachment_path is null or attachment_path like auth.uid()::text || '/%')
  );

create policy "помощник: правят ждущее своё" on assistant_messages
  for update to authenticated
  using (from_user and handled_at is null and (
    (channel = 'assistant' and is_assistant_owner())
    or (channel = 'bugs' and author_id = auth.uid() and is_app_tester())
  ))
  with check (from_user and handled_at is null and (
    (channel = 'assistant' and is_assistant_owner())
    or (channel = 'bugs' and author_id = auth.uid() and is_app_tester())
  ));

create policy "помощник: удаляют ждущее своё" on assistant_messages
  for delete to authenticated
  using (from_user and handled_at is null and (
    (channel = 'assistant' and is_assistant_owner())
    or (channel = 'bugs' and author_id = auth.uid() and is_app_tester())
  ));

-- ── скриншоты тестировщика ──────────────────────────────────────────────────

create policy "assistant: тестировщик читает свои файлы" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'assistant'
    and is_app_tester()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "assistant: тестировщик грузит в свою папку" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'assistant'
    and is_app_tester()
    and (storage.foldername(name))[1] = auth.uid()::text
  );
