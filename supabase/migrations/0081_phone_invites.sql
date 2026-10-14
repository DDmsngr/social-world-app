-- Приглашение по номеру телефона. Раньше связь «пригласил → пришёл» появлялась
-- только если приглашённый сам вводил код или открывал ссылку до установки; кто
-- просто получил файл и поставил его, терялся, и очки не начислялись.
--
-- Теперь, приглашая человека из контактов, приложение запоминает хеш его номера
-- (сам номер на сервер не уходит). Когда человек входит через VK или Яндекс и
-- провайдер отдаёт его подтверждённый номер (set_verified_phone), совпавшее
-- приглашение превращается в обычную запись referrals с источником 'phone'.

alter table referrals drop constraint referrals_source_check;
alter table referrals add constraint referrals_source_check
  check (source in ('link', 'clipboard', 'manual', 'phone'));

-- Кого и кто позвал. Хеш уже в том же виде, что и в profile_phones (phone_hmac).
create table phone_invites (
  inviter_id uuid not null references profiles(id) on delete cascade,
  phone_hash text not null check (phone_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (inviter_id, phone_hash)
);
create index phone_invites_hash_idx on phone_invites (phone_hash, created_at);
alter table phone_invites enable row level security;
revoke all on phone_invites from public, anon, authenticated;

-- Клиент: «я позвал людей с такими номерами» (хеши, как в сверке контактов).
create function record_phone_invites(p_hashes text[]) returns integer
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  n integer := 0;
  h text;
begin
  if me is null then raise exception 'нужен вход'; end if;
  if coalesce(array_length(p_hashes, 1), 0) > 20 then
    raise exception 'слишком много номеров за раз';
  end if;
  if (select count(*) from phone_invites where inviter_id = me and created_at > now() - interval '1 day') >= 100 then
    return 0;
  end if;
  foreach h in array coalesce(p_hashes, '{}') loop
    continue when h is null or h !~ '^[0-9a-f]{64}$';
    insert into phone_invites (inviter_id, phone_hash) values (me, phone_hmac(h))
    on conflict (inviter_id, phone_hash) do update set created_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;

revoke all on function record_phone_invites(text[]) from public, anon;
grant execute on function record_phone_invites(text[]) to authenticated;

-- Можно ли ещё указать пригласившего: программа включена, профиль моложе
-- claim_days и пригласившего нет. По этому флагу приложение решает, спрашивать
-- ли после регистрации «Вас кто-то пригласил?» (у старых пользователей не надо).
create function referral_claim_open() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null
     and exists (
       select 1 from referral_settings s, profiles p
       where s.enabled and p.id = auth.uid()
         and p.created_at >= now() - make_interval(days => s.claim_days)
     )
     and not exists (select 1 from referrals where invitee_id = auth.uid());
$$;

revoke all on function referral_claim_open() from public, anon;
grant execute on function referral_claim_open() to authenticated;

-- Связь по подтверждённому номеру. Зовёт set_verified_phone сразу после того, как
-- номер записан. Тихо выходит, если связывать нечего или нельзя: вход не должен
-- из-за этого ломаться. Проверок устройства здесь нет (приложение ещё не
-- присылало отпечаток), поэтому берём только приглашение, сделанное за 30 дней
-- до регистрации, и те же ограничения на петли и лимит, что у claim_referral.
create function referral_claim_by_phone(p_profile uuid, p_stored text) returns void
language plpgsql security definer set search_path = public as $$
declare
  s referral_settings;
  created timestamptz;
  inviter uuid;
begin
  select * into s from referral_settings;
  if not s.enabled then return; end if;
  if exists (select 1 from referrals where invitee_id = p_profile) then return; end if;
  select created_at into created from profiles where id = p_profile;
  if created is null or created < now() - make_interval(days => s.claim_days) then return; end if;

  select i.inviter_id into inviter
  from phone_invites i
  join profiles p on p.id = i.inviter_id and p.status <> 'blocked'
  where i.phone_hash = p_stored
    and i.inviter_id <> p_profile
    and i.created_at > now() - interval '30 days'
  order by i.created_at
  limit 1;
  if inviter is null then return; end if;

  if exists (select 1 from referral_ancestors(inviter, 50) a where a.profile_id = p_profile) then return; end if;
  if (select count(*) from referrals where inviter_id = inviter and created_at > now() - interval '1 day')
      >= s.daily_invite_limit then
    return;
  end if;

  insert into referrals (invitee_id, inviter_id, code, source, status, fraud_score, fraud_reasons)
  values (p_profile, inviter, referral_ensure_code(inviter), 'phone', 'waiting', 0, '{phone_invite}');

  perform add_notification(inviter, p_profile, 'referral_joined', 'points', p_profile, null);
  perform referral_log(p_profile, 'referral_registered',
    jsonb_build_object('inviter', inviter, 'source', 'phone', 'status', 'waiting', 'score', 0));
end $$;

revoke all on function referral_claim_by_phone(uuid, text) from public, anon, authenticated;

-- Подтверждённый номер записан → пробуем связать с приглашением по номеру.
create or replace function set_verified_phone(p_profile uuid, p_hash text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  stored text;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'некорректный номер';
  end if;
  stored := phone_hmac(p_hash);

  delete from profile_phones
  where phone_hash = stored and profile_id <> p_profile and not verified;
  if exists (select 1 from profile_phones where phone_hash = stored and profile_id <> p_profile) then
    return false;
  end if;

  insert into profile_phones (profile_id, phone_hash, verified)
  values (p_profile, stored, true)
  on conflict (profile_id) do update
    set phone_hash = excluded.phone_hash, verified = true;

  begin
    perform referral_claim_by_phone(p_profile, stored);
  exception when others then
    -- Реферальная связь — приятное дополнение: сбой в ней не должен отменять
    -- подтверждение номера и ломать вход. Но и молчать нельзя: ошибка
    -- остаётся в журнале событий (analytics_events, referral_claim_failed).
    begin
      perform referral_log(p_profile, 'referral_claim_failed',
        jsonb_build_object('error', sqlerrm, 'state', sqlstate));
    exception when others then
      null;
    end;
  end;
  return true;
end $$;
