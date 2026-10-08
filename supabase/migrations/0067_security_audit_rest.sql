-- Остаток аудита безопасности 08.10: №4 (функция доступа к каналам Realtime,
-- сами политики — в 0067b, их ставит владелец realtime.messages), №5 (номера
-- телефонов: HMAC и лимит сверки), №8 (ссылки на медиа только на свои файлы),
-- №11 (начало и конец маршрута скрыты от чужих).

-- ── №4. Кто может слушать и слать в broadcast-канал ─────────────────────────
-- call:<id>   — только звонящий и вызываемый;
-- typing:<id> — только участники чата.
-- Остальные темы broadcast не используются, в них никого не пускаем.

create function realtime_topic_allowed(in_topic text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when in_topic ~ '^call:[0-9a-f-]{36}$' then exists (
      select 1 from calls c
      where c.id = substr(in_topic, 6)::uuid
        and auth.uid() in (c.caller_id, c.callee_id)
    )
    when in_topic ~ '^typing:[0-9a-f-]{36}$' then exists (
      select 1 from chat_members m
      where m.conversation_id = substr(in_topic, 8)::uuid
        and m.profile_id = auth.uid()
    )
    else false
  end;
$$;

revoke all on function realtime_topic_allowed(text) from public, anon;
grant execute on function realtime_topic_allowed(text) to authenticated;

-- ── №5. Номера телефонов ────────────────────────────────────────────────────
-- Голый SHA-256 номера перебирается за секунды. Теперь в базе лежит
-- HMAC-SHA256 от него с серверным ключом из vault: утёкшая таблица без ключа
-- бесполезна. Телефон по-прежнему шлёт SHA-256, приложение менять не нужно.
-- От перебора через саму сверку защищает дневной лимит.

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'phone_hash_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'phone_hash_key',
      'Ключ HMAC для хешей номеров телефонов (0067)'
    );
  end if;
end $$;

create function phone_hmac(in_hash text) returns text
language sql stable security definer set search_path = public as $$
  select encode(
    extensions.hmac(
      in_hash,
      (select decrypted_secret from vault.decrypted_secrets where name = 'phone_hash_key'),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function phone_hmac(text) from public, anon, authenticated;

update profile_phones set phone_hash = phone_hmac(phone_hash);

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
  return true;
end $$;

create or replace function set_my_phone(p_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'некорректный номер';
  end if;
  if exists (select 1 from profile_phones where profile_id = auth.uid() and verified) then
    raise exception 'номер уже подтверждён через вход, менять его нельзя';
  end if;
  insert into profile_phones (profile_id, phone_hash, verified)
  values (auth.uid(), phone_hmac(p_hash), false)
  on conflict (profile_id) do update set phone_hash = excluded.phone_hash;
exception when unique_violation then
  raise exception 'этот номер уже привязан к другому профилю';
end $$;

-- Сколько номеров человек сверил за день. Сами номера не храним.
create table contact_match_usage (
  profile_id uuid not null references profiles on delete cascade,
  day        date not null default current_date,
  hashes     integer not null default 0,
  primary key (profile_id, day)
);

alter table contact_match_usage enable row level security;
revoke all on contact_match_usage from public, anon, authenticated;

-- Записная книжка обычного человека — сотни, редко пара тысяч номеров.
-- 10 000 в сутки хватает на несколько пересканов, а перебор номеров страны
-- на таком темпе бессмыслен.
create or replace function match_contacts(p_hashes text[])
returns table (phone_hash text, id uuid, display_name text, avatar_url text, followed_by_me boolean, verified boolean)
language plpgsql volatile security definer set search_path = public as $$
declare
  n    integer := coalesce(array_length(p_hashes, 1), 0);
  used integer;
  k    text;
begin
  if auth.uid() is null then raise exception 'нужен вход'; end if;
  if n > 1000 then
    raise exception 'слишком много контактов за раз';
  end if;

  insert into contact_match_usage as u (profile_id, day, hashes)
  values (auth.uid(), current_date, n)
  on conflict (profile_id, day) do update set hashes = u.hashes + excluded.hashes
  returning u.hashes into used;
  if used > 10000 then
    raise exception 'rate_limit: сверка контактов на сегодня исчерпана';
  end if;

  delete from contact_match_usage where day < current_date - 7;

  select decrypted_secret into k from vault.decrypted_secrets where name = 'phone_hash_key';

  return query
  select i.h, p.id, coalesce(p.display_name, 'Без имени'), p.avatar_url,
         exists (
           select 1 from follows f
           where f.follower_id = auth.uid()
             and f.target_type = 'profile' and f.target_id = p.id
         ),
         ph.verified
  from unnest(p_hashes) as i(h)
  join profile_phones ph on ph.phone_hash = encode(extensions.hmac(i.h, k, 'sha256'), 'hex')
  join profiles p on p.id = ph.profile_id
  where p.id <> auth.uid()
    and p.status <> 'blocked';
end $$;

-- ── №8. Ссылки на медиа — только на свои файлы в своём хранилище ────────────
-- Иначе в аватар или пост можно вписать адрес чужого сервера: телефоны всех,
-- кто это увидит, сходят туда и отдадут свой IP, а содержимое пройдёт мимо
-- модерации. Проверяются только записи от пользователя (есть auth.uid()):
-- сервер (мост входа VK/Яндекс ставит аватар провайдера) и миграции не
-- ограничены. Неизменённое значение при UPDATE не проверяется.

create function media_url_ok(in_url text, in_bucket text, in_owner uuid) returns boolean
language sql immutable set search_path = public as $$
  select in_url ~ (
    '^https://api-socialworld\.deepdrift\.tech/storage/v1/object/public/'
    || in_bucket || '/' || in_owner::text || '/[A-Za-z0-9._-]+$'
  );
$$;

grant execute on function media_url_ok(text, text, uuid) to authenticated;

-- Аргументы триггера: колонка, бакет, чей файл — имя колонки-владельца или
-- '@me' (текущий пользователь), '@route' (автор маршрута из route_id).
create function check_media_urls() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  col    text := tg_argv[0];
  bucket text := tg_argv[1];
  owner_ref text := tg_argv[2];
  fresh  jsonb := to_jsonb(new) -> col;
  owner  uuid;
  url    text;
begin
  if auth.uid() is null or fresh is null or jsonb_typeof(fresh) = 'null' then
    return new;
  end if;
  if tg_op = 'UPDATE' and fresh = to_jsonb(old) -> col then
    return new;
  end if;

  owner := case owner_ref
    when '@me' then auth.uid()
    when '@route' then (select r.author_id from routes r where r.id = (to_jsonb(new) ->> 'route_id')::uuid)
    else (to_jsonb(new) ->> owner_ref)::uuid
  end;

  for url in
    select value from jsonb_array_elements_text(
      case jsonb_typeof(fresh) when 'array' then fresh else jsonb_build_array(fresh) end
    )
  loop
    if owner is null or not media_url_ok(url, bucket, owner) then
      raise exception 'ссылка не на ваш файл' using errcode = '22023';
    end if;
  end loop;
  return new;
end $$;

revoke all on function check_media_urls() from public, anon, authenticated;

create trigger profiles_avatar_url_check before insert or update of avatar_url on profiles
  for each row execute function check_media_urls('avatar_url', 'avatars', 'id');
create trigger profiles_avatar_video_check before insert or update of avatar_video_url on profiles
  for each row execute function check_media_urls('avatar_video_url', 'avatars', 'id');
create trigger posts_media_check before insert or update of media_urls on posts
  for each row execute function check_media_urls('media_urls', 'post-media', 'author_id');
create trigger post_comments_media_check before insert or update of media_urls on post_comments
  for each row execute function check_media_urls('media_urls', 'post-media', 'author_id');
create trigger stories_media_check before insert or update of media_url on stories
  for each row execute function check_media_urls('media_url', 'post-media', 'author_id');
create trigger route_photos_url_check before insert or update of photo_url on route_photos
  for each row execute function check_media_urls('photo_url', 'route-photos', '@route');
create trigger events_cover_check before insert or update of cover_url on events
  for each row execute function check_media_urls('cover_url', 'post-media', 'author_id');
create trigger quests_photo_check before insert or update of photo_url on quests
  for each row execute function check_media_urls('photo_url', 'post-media', 'author_id');
create trigger chat_conversations_avatar_check before insert or update of avatar_url on chat_conversations
  for each row execute function check_media_urls('avatar_url', 'avatars', '@me');

-- ── №11. Начало и конец маршрута ────────────────────────────────────────────
-- Запись часто начинается от дома. Чужим route_detail отдаёт путь без первых
-- и последних 200 м (у коротких — не больше четверти длины с каждой стороны)
-- и без фото, снятых в этих зонах. Автор видит всё. Прямое чтение таблицы
-- routes оставлено только автору: иначе полный путь читался бы мимо функции.

do $$
declare r record;
begin
  for r in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'routes' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on routes', r.policyname);
  end loop;
end $$;

create policy routes_select_own
  on routes for select to authenticated
  using (author_id = auth.uid());

create or replace function route_detail(in_route uuid)
returns table (
  id          uuid,
  author_id   uuid,
  author_name text,
  avatar_url  text,
  title       text,
  path        jsonb,
  distance_m  integer,
  duration_s  integer,
  started_at  timestamptz,
  created_at  timestamptz,
  photos      jsonb
)
language sql stable security definer set search_path = public as $$
  with r as (
    select r.*,
           r.author_id = auth.uid() as mine,
           least(200, st_length(r.path) / 4) as hide_m,
           st_length(r.path) as len_m
    from routes r
    where r.id = in_route
      and r.status <> 'blocked'
      and can_see_route(r.author_id, r.visibility, r.link_access)
  )
  select r.id,
         r.author_id,
         pr.display_name,
         pr.avatar_url,
         r.title,
         st_asgeojson(
           case
             when r.mine or r.len_m <= 0 then r.path::geometry
             -- В проекции 3857 масштаб на масштабе города одинаков по всем
             -- направлениям, поэтому доля длины в метрах переносится как есть.
             else st_transform(
               st_linesubstring(
                 st_transform(r.path::geometry, 3857),
                 r.hide_m / r.len_m,
                 1 - r.hide_m / r.len_m
               ),
               4326
             )
           end
         )::jsonb,
         r.distance_m,
         r.duration_s,
         r.started_at,
         r.created_at,
         coalesce(
           (select jsonb_agg(
                     jsonb_build_object(
                       'id', rp.id,
                       'photo_url', rp.photo_url,
                       'caption', rp.caption,
                       'taken_at', rp.taken_at,
                       'latitude', st_y(rp.geo::geometry),
                       'longitude', st_x(rp.geo::geometry)
                     ) order by rp.taken_at
                   )
              from route_photos rp
             where rp.route_id = r.id
               and (
                 r.mine
                 or not (
                   st_dwithin(rp.geo, st_startpoint(r.path::geometry)::geography, r.hide_m)
                   or st_dwithin(rp.geo, st_endpoint(r.path::geometry)::geography, r.hide_m)
                 )
               )),
           '[]'::jsonb
         )
  from r
  join profiles pr on pr.id = r.author_id
  where pr.status <> 'blocked';
$$;

revoke all on function route_detail from public, anon;
grant execute on function route_detail to authenticated;
