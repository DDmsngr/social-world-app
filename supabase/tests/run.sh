#!/usr/bin/env bash
# Прогон SQL-проверок чата на временной базе.
#
#   PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run.sh
#
# Нужен обычный PostgreSQL 14+ с правом создавать базы и роли — Supabase
# поднимать не надо. Недостающее окружение Supabase (схемы auth и storage,
# роли anon/authenticated, публикация realtime, profiles и пара таблиц)
# заменяют заглушки ниже, а сами миграции берутся из репозитория как есть:
# 0003 целиком, нужные куски 0030, 0032, 0033 и 0034 целиком.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
migrations="$here/../migrations"
db="chawo_chat_test_$$"
sql="$(mktemp)"
trap 'rm -f "$sql"; dropdb --if-exists "$db" >/dev/null 2>&1 || true' EXIT

python3 - "$migrations" "$sql" <<'PY'
import re, sys
migrations, out = sys.argv[1], sys.argv[2]

def read(name):
    return open(f"{migrations}/{name}", encoding="utf-8").read()

def between(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)]

stubs = """
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create publication supabase_realtime;
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid default auth.uid());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
grant usage on schema auth, storage, public to authenticated, anon;
create table profiles (id uuid primary key, display_name text, avatar_url text, status text not null default 'active');
create table quests (id uuid primary key, title text);
create table user_blocks (blocker_id uuid, blocked_id uuid, kind text default 'block');
create function enforce_rate_limit() returns trigger language plpgsql as $$ begin return new; end $$;
"""

# То, что 0030 и 0032 берут из 0014/0023 (миграции вне чата).
from_other = """
alter table chat_conversations add column if not exists closed_at timestamptz,
                               add column if not exists quest_id uuid;
create function is_chat_open(in_conversation uuid) returns boolean language sql stable
  security definer set search_path = public set row_security = off as $$
  select not exists (select 1 from chat_conversations where id = in_conversation and closed_at is not null) $$;
grant insert on chat_messages to authenticated;
grant insert, update on chat_public_keys to authenticated;
create policy chat_messages_open_only on chat_messages as restrictive for insert to authenticated with check (true);
"""

m30 = read("0030_chats_on_groups_follow_lists.sql")
groups = between(m30, "-- ── 2. Схема групп", "-- ── 4. Подписчики")

parts = [stubs, read("0003_chat.sql"), from_other, groups,
         read("0032_chat_attachments.sql"), read("0033_chat_message_delete.sql"),
         read("0034_chat_reply_forward_scheduled.sql")]
open(out, "w", encoding="utf-8").write("\n;\n".join(parts))
PY

createdb "$db"
export PGDATABASE="$db"
psql -v ON_ERROR_STOP=1 -q -f "$sql" 2>&1 | grep -vE 'NOTICE|WARNING|HINT' || true
psql -v ON_ERROR_STOP=1 -q -t -A -f "$here/chat_delete_and_scheduled.sql" 2>&1 \
  | grep -vE 'NOTICE|WARNING|^$|^==' 
