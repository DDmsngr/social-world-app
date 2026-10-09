-- 0060 Трансляция геопозиции в чатах: 15 мин / 30 мин / час / пока не выключу.
--
-- Одна строка — одна трансляция человека в одном чате. Последняя точка лежит в
-- самой строке и обновляется на месте; таблица в публикации Realtime, поэтому
-- собеседники видят движение без опроса. Истории перемещений сервер не хранит.
--
-- В личных чатах точка зашифрована на клиенте тем же ключом пары, что и
-- сообщения (ciphertext/nonce/mac/signature), сервер координат не видит.
-- В группах сообщения открытые — там и точка открытая (lat/lng).

create table if not exists public.live_locations (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  -- null — «пока не выключу»
  expires_at timestamptz,
  stopped_at timestamptz,
  ciphertext text,
  nonce text,
  mac text,
  signature text,
  lat double precision,
  lng double precision,
  accuracy real,
  updated_at timestamptz
);

create index if not exists live_locations_active_idx
  on public.live_locations (conversation_id)
  where stopped_at is null;

alter table public.live_locations enable row level security;

drop policy if exists live_locations_select on public.live_locations;
create policy live_locations_select on public.live_locations
  for select to authenticated
  using (public.is_chat_member(conversation_id));

-- Писать только через функции ниже.
revoke all on public.live_locations from anon;
revoke insert, update, delete on public.live_locations from authenticated;
grant select on public.live_locations to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'live_locations'
  ) then
    alter publication supabase_realtime add table public.live_locations;
  end if;
end $$;

-- Начать трансляцию. in_minutes null — пока не выключу. Прежняя трансляция
-- этого человека в этом чате закрывается: одновременно идёт одна.
create or replace function public.start_live_location(in_conversation uuid, in_minutes integer)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_chat_member(in_conversation) then
    raise exception 'not a member';
  end if;
  if exists (select 1 from chat_conversations where id = in_conversation and (is_channel or closed_at is not null)) then
    raise exception 'live location is not available here';
  end if;
  if in_minutes is not null and (in_minutes < 1 or in_minutes > 24 * 60) then
    raise exception 'bad duration';
  end if;

  update live_locations
     set stopped_at = now()
   where conversation_id = in_conversation and user_id = me and stopped_at is null;

  insert into live_locations (conversation_id, user_id, expires_at)
  values (
    in_conversation,
    me,
    case when in_minutes is null then null else now() + make_interval(mins => in_minutes) end
  )
  returning id into new_id;
  return new_id;
end;
$$;

-- Новая точка. false — трансляция уже закончилась (истекла или выключена):
-- клиент по этому сигналу останавливает отправку.
create or replace function public.update_live_location(
  in_id uuid,
  in_ciphertext text default null,
  in_nonce text default null,
  in_mac text default null,
  in_signature text default null,
  in_lat double precision default null,
  in_lng double precision default null,
  in_accuracy real default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  row_ live_locations%rowtype;
begin
  select * into row_ from live_locations where id = in_id and user_id = me;
  if not found or row_.stopped_at is not null then
    return false;
  end if;
  if row_.expires_at is not null and row_.expires_at <= now() then
    update live_locations set stopped_at = row_.expires_at where id = in_id;
    return false;
  end if;
  -- Чаще раза в 3 секунды не пишем: от дребезга GPS толку нет.
  if row_.updated_at is not null and row_.updated_at > now() - interval '3 seconds' then
    return true;
  end if;

  update live_locations
     set ciphertext = in_ciphertext,
         nonce = in_nonce,
         mac = in_mac,
         signature = in_signature,
         lat = in_lat,
         lng = in_lng,
         accuracy = in_accuracy,
         updated_at = now()
   where id = in_id;
  return true;
end;
$$;

create or replace function public.stop_live_location(in_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update live_locations
     set stopped_at = now()
   where id = in_id and user_id = auth.uid() and stopped_at is null;
$$;

revoke all on function public.start_live_location(uuid, integer) from public, anon;
revoke all on function public.update_live_location(uuid, text, text, text, text, double precision, double precision, real) from public, anon;
revoke all on function public.stop_live_location(uuid) from public, anon;
grant execute on function public.start_live_location(uuid, integer) to authenticated;
grant execute on function public.update_live_location(uuid, text, text, text, text, double precision, double precision, real) to authenticated;
grant execute on function public.stop_live_location(uuid) to authenticated;

-- Истёкшие трансляции закрываем сами: у человека могло умереть приложение, и
-- update_live_location больше не придёт.
create or replace function public.live_locations_expire()
returns void
language sql
security definer
set search_path = public
as $$
  update live_locations
     set stopped_at = coalesce(expires_at, now())
   where stopped_at is null
     and (
       (expires_at is not null and expires_at <= now())
       -- «Пока не выключу», но точек нет сутки — телефон пропал, закрываем.
       or (expires_at is null and coalesce(updated_at, started_at) < now() - interval '24 hours')
     );
$$;

revoke all on function public.live_locations_expire() from public, anon, authenticated;

select cron.schedule('live-locations-expire', '* * * * *', 'select public.live_locations_expire()')
where not exists (select 1 from cron.job where jobname = 'live-locations-expire');
