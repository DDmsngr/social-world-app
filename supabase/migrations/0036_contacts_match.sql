-- Поиск знакомых из записной книжки. Номер телефона в базу не попадает:
-- приложение считает SHA-256 от нормализованного номера (только цифры,
-- 8… → 7…) и присылает хеш. Человек сам решает, привязывать ли свой номер.

create table profile_phones (
  profile_id uuid primary key references profiles on delete cascade,
  phone_hash text not null unique check (phone_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

-- Таблица закрыта целиком: читать и писать только через функции ниже.
alter table profile_phones enable row level security;
revoke all on profile_phones from public, anon, authenticated;

create function set_my_phone(p_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'некорректный номер';
  end if;
  insert into profile_phones (profile_id, phone_hash)
  values (auth.uid(), p_hash)
  on conflict (profile_id) do update set phone_hash = excluded.phone_hash;
exception when unique_violation then
  raise exception 'этот номер уже привязан к другому профилю';
end $$;

create function clear_my_phone() returns void
language sql security definer set search_path = public as $$
  delete from profile_phones where profile_id = auth.uid();
$$;

create function has_my_phone() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profile_phones where profile_id = auth.uid());
$$;

-- Кто из присланных хешей уже в ChaWo. Себя и заблокированных не отдаём.
create function match_contacts(p_hashes text[])
returns table (phone_hash text, id uuid, display_name text, avatar_url text, followed_by_me boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if coalesce(array_length(p_hashes, 1), 0) > 5000 then
    raise exception 'слишком много контактов за раз';
  end if;
  return query
  select ph.phone_hash, p.id, coalesce(p.display_name, 'Без имени'), p.avatar_url,
         exists (
           select 1 from follows f
           where f.follower_id = auth.uid()
             and f.target_type = 'profile' and f.target_id = p.id
         )
  from profile_phones ph
  join profiles p on p.id = ph.profile_id
  where ph.phone_hash = any (p_hashes)
    and p.id <> auth.uid()
    and p.status <> 'blocked';
end $$;

revoke all on function set_my_phone(text), clear_my_phone(), has_my_phone(),
  match_contacts(text[]) from public, anon;
grant execute on function set_my_phone(text), clear_my_phone(), has_my_phone(),
  match_contacts(text[]) to authenticated;
