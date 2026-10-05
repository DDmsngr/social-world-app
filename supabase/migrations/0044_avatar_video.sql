-- Видеоаватар (короткий зацикленный кружок вместо фото) — задел под премиум.
--
-- Что есть после этой миграции:
--   * profiles.avatar_video_url — ссылка на ролик в бакете avatars;
--   * profiles.premium_until — до какого момента у человека премиум. Клиент
--     писать её не может (колонки нет в column-grant из 0011), выставляет
--     сервер или администратор;
--   * my_is_premium() — премиум ли я сейчас;
--   * set_avatar_video(url) — единственный путь записать видеоаватар. Ставить
--     может только премиум и только ссылку на СВОЮ папку в avatars; убрать
--     (null) можно всегда, даже после окончания премиума;
--   * profile_card отдаёт avatar_video_url, чтобы чужой профиль мог его
--     показать.
-- Клиентский флаг Features.videoAvatar пока выключен: механика готова, а
-- решение, когда и кому её открыть, — продуктовое.

alter table profiles
  add column avatar_video_url text
    check (avatar_video_url is null or char_length(avatar_video_url) <= 500),
  add column premium_until timestamptz;

create function my_is_premium() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select premium_until > now() from profiles where id = auth.uid()),
    false
  );
$$;

create function set_avatar_video(in_url text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'authentication required'; end if;

  if in_url is null then
    update profiles set avatar_video_url = null where id = me;
    return;
  end if;

  if not my_is_premium() then
    raise exception 'видеоаватар доступен в премиуме';
  end if;
  -- Только свой файл из публичного бакета avatars: чужую ссылку или
  -- произвольный адрес сюда не принять.
  if in_url !~ ('/storage/v1/object/public/avatars/' || me::text || '/[^/]+\.(mp4|mov|webm)$') then
    raise exception 'ссылка не на ваш ролик';
  end if;

  update profiles set avatar_video_url = in_url where id = me;
end;
$$;

-- profile_card теперь с avatar_video_url: сменился состав колонок результата,
-- поэтому drop + create и права заново (как в 0027 — анонимам не отдаём).
drop function profile_card(uuid);
create function profile_card(in_profile uuid)
returns table (
  id               uuid,
  display_name     text,
  avatar_url       text,
  bio              text,
  city             text,
  social_score     integer,
  follower_count   bigint,
  following_count  bigint,
  followed_by_me   boolean,
  block_kind       text,
  avatar_video_url text
)
language sql stable security definer set search_path = public as $$
  select p.id,
         p.display_name,
         p.avatar_url,
         p.bio,
         p.city,
         p.social_score,
         (select count(*) from follows f
           where f.target_type = 'profile' and f.target_id = p.id),
         (select count(*) from follows f
           where f.follower_id = p.id and f.target_type = 'profile'),
         exists (select 1 from follows f
                  where f.follower_id = auth.uid()
                    and f.target_type = 'profile' and f.target_id = p.id),
         (select b.kind from user_blocks b
           where b.blocker_id = auth.uid() and b.blocked_id = p.id),
         -- Видеоаватар показываем, только пока у владельца действует премиум.
         case when p.premium_until > now() then p.avatar_video_url end
  from profiles p
  where p.id = in_profile
    and p.status <> 'blocked'
    and not exists (
      select 1 from user_blocks b
      where b.blocker_id = p.id and b.blocked_id = auth.uid() and b.kind = 'block'
    );
$$;

revoke all on function my_is_premium(), set_avatar_video(text), profile_card(uuid)
  from public, anon;
grant execute on function my_is_premium(), set_avatar_video(text), profile_card(uuid)
  to authenticated;
