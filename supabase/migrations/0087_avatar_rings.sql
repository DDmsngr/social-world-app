-- Кайма вокруг аватара: золотая у команды проекта, зелёная у тестировщиков.
--
-- Видна всем: это знак «свой». Список короткий, приложение берёт его одним
-- вызовом и рисует кольцо везде, где знает, чей аватар.

create table team_members (
  profile_id uuid primary key references profiles on delete cascade,
  added_at   timestamptz not null default now()
);
alter table team_members enable row level security;
revoke all on team_members from public, anon, authenticated;

-- Алексей и Левон.
insert into team_members (profile_id)
select id from profiles
where id in ('71b20b93-1d0f-4671-af42-576809d176f9', 'de2b4557-5cd9-4b8a-b45a-c6d10a762a3a')
on conflict do nothing;

create function profile_rings() returns table (profile_id uuid, ring text)
language sql stable security definer set search_path = public set row_security = off as $$
  select t.profile_id, 'gold' from team_members t
  union all
  select a.profile_id, 'green' from app_testers a
  where not exists (select 1 from team_members t where t.profile_id = a.profile_id);
$$;

revoke all on function profile_rings() from public, anon;
grant execute on function profile_rings() to authenticated;
