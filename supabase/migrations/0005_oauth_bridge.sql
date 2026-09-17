-- Мост входа через VK ID и Яндекс ID (см. supabase/functions в volumes/functions
-- на VM — сам код мостов туда не попадает, edge-функции не версионируются в
-- этом репо, только их SQL-опора).
--
-- Наш self-hosted GoTrue не знает VK/Яндекс как провайдеров — это обходится
-- Edge Function'ами, которые сами делают OAuth-обмен и заводят пользователя
-- через Admin API. Здесь — то, что им нужно на стороне БД.

-- Однократный код+верификатор PKCE между шагом start и callback. Живёт
-- секунды-минуты, потому и без RLS-политик: доступ только через service_role,
-- которым и работают Edge Functions.
create table oauth_pkce_state (
  state         text primary key,
  provider      text not null,
  code_verifier text,
  created_at    timestamptz not null default now()
);

alter table oauth_pkce_state enable row level security;

-- Привязка внешнего аккаунта к профилю. Один и тот же VK/Яндекс аккаунт
-- всегда должен вести на один и тот же profile_id, даже если email у
-- провайдера пустой или менялся.
create table oauth_identities (
  provider    text not null,
  external_id text not null,
  profile_id  uuid not null references profiles on delete cascade,
  email       text,
  created_at  timestamptz not null default now(),
  primary key (provider, external_id)
);

create index oauth_identities_profile_idx on oauth_identities (profile_id);

alter table oauth_identities enable row level security;

create policy "вижу только свои привязки"
  on oauth_identities for select to authenticated
  using (auth.uid() = profile_id);
