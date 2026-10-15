-- Аудит безопасности 15.10.2026: мелочи, которые закрываются без изменений
-- в приложении.

-- 1. chat_peer_online: «в сети» спрашивала любая подписка, знающая id чата
--    (у каналов он публичный), в обход скрытия последнего визита. Теперь
--    пользователь должен состоять в этом чате. Сервер (push-send, service_role)
--    без auth.uid() работает как раньше.
create or replace function chat_peer_online(in_conversation uuid, in_sender uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select (auth.uid() is null
          or exists (select 1 from chat_members me
                      where me.conversation_id = in_conversation
                        and me.profile_id = auth.uid()))
     and exists (
       select 1
         from chat_members m
         join user_presence p on p.profile_id = m.profile_id
        where m.conversation_id = in_conversation
          and m.profile_id <> in_sender
          and p.seen_at > now() - interval '2 minutes'
     );
$$;

-- 2. Лишние права на запись. Таблицы закрыты RLS без политик, и сейчас писать
--    в них нельзя, но одна будущая политика открыла бы запись всем.
--    Пишет в них только сервер.
revoke insert, update, delete, truncate, references, trigger
  on activity_config, analytics_events, device_sightings, oauth_pkce_state
  from anon, authenticated;

-- 3. Аватар канала — только файл владельца в нашем хранилище (как у аватара
--    профиля, 0067). Раньше принималась любая https-ссылка: все, кто откроет
--    канал, сходили бы по ней и отдали владельцу ссылки свой IP.
create or replace function set_channel_avatar(in_channel uuid, in_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if in_url is not null and (char_length(in_url) > 500
      or not media_url_ok(in_url, 'avatars', auth.uid())) then
    raise exception 'некорректная ссылка';
  end if;
  if not exists (
    select 1 from chat_members m
    join chat_conversations c on c.id = m.conversation_id
    where m.conversation_id = in_channel
      and m.profile_id = auth.uid()
      and m.role in ('owner', 'admin')
      and c.direct_key is null
  ) then
    raise exception 'менять аватар может только владелец или админ';
  end if;
  update chat_conversations set avatar_url = in_url where id = in_channel;
end;
$$;
