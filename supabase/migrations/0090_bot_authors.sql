-- Виртуальные авторы ChaWo: аккаунты, которые ведёт редакция и которые
-- честно помечены. Решение Алексея 14.10.2026: метка «ИИ-автор» и своя
-- фиолетовая кайма у аватара, чтобы никто не принял их за живых людей.
--
-- bot_authors — список таких профилей. Кайма: profile_rings() теперь отдаёт
-- 'violet' для них (поверх прежних золота у команды и зелёного у тестировщиков).
-- Публикуют от их имени с серверной стороны (service_role): входа в эти
-- аккаунты у людей нет.

create table bot_authors (
  profile_id uuid primary key references profiles on delete cascade,
  topic      text not null,
  added_at   timestamptz not null default now()
);
alter table bot_authors enable row level security;
revoke all on bot_authors from public, anon, authenticated;
grant all on bot_authors to service_role;

create or replace function profile_rings() returns table (profile_id uuid, ring text)
language sql stable security definer set search_path = public set row_security = off as $$
  select t.profile_id, 'gold' from team_members t
  union all
  select b.profile_id, 'violet' from bot_authors b
  where not exists (select 1 from team_members t where t.profile_id = b.profile_id)
  union all
  select a.profile_id, 'green' from app_testers a
  where not exists (select 1 from team_members t where t.profile_id = a.profile_id)
    and not exists (select 1 from bot_authors b where b.profile_id = a.profile_id);
$$;
