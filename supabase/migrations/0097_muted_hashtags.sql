-- Скрытые теги переезжают вместе с аккаунтом (Алексей, 15.10.2026): игнор-лист
-- раньше жил только на телефоне. Ленту фильтрует приложение, сервер лишь
-- хранит список. Каждый видит и меняет только свой.

create table muted_hashtags (
  profile_id uuid not null references profiles on delete cascade default auth.uid(),
  tag        text not null check (tag ~ '^[[:alnum:]_]{2,50}$' and tag = lower(tag)),
  created_at timestamptz not null default now(),
  primary key (profile_id, tag)
);

alter table muted_hashtags enable row level security;
revoke all on muted_hashtags from public, anon;
grant select, insert, delete on muted_hashtags to authenticated;

create policy "свои скрытые теги" on muted_hashtags for select to authenticated
  using (profile_id = auth.uid());
create policy "скрываю тег себе" on muted_hashtags for insert to authenticated
  with check (profile_id = auth.uid()
    and (select count(*) from muted_hashtags m where m.profile_id = auth.uid()) < 300);
create policy "возвращаю свой тег" on muted_hashtags for delete to authenticated
  using (profile_id = auth.uid());
