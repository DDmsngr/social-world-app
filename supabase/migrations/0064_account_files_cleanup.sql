-- Удаление аккаунта стирает и файлы.
--
-- Раньше delete_my_account (0061) удаляла строки в базе, а файлы в хранилище
-- (аватар, фото публикаций и маршрутов, вложения чатов, файлы помощника)
-- оставались лежать. Теперь они уходят в ту же очередь на удаление, что и
-- вложения удалённых сообщений (chat_media_trash, 0035): её каждые 10 минут
-- разбирает функция chat-media-gc.
--
-- Очередь была только для бакета chat-media, поэтому в неё добавляется бакет.

alter table chat_media_trash add column bucket text not null default 'chat-media';
alter table chat_media_trash drop constraint chat_media_trash_pkey;
alter table chat_media_trash add primary key (bucket, path);

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- Аккаунт команды (дашборд) удаляется вручную: там задачи и переписка команды.
  if exists (select 1 from public.ws_members where user_id = me) then
    raise exception 'team account: delete via support' using errcode = '42501';
  end if;

  -- Вложения моих сообщений: сообщения исчезнут вместе с аккаунтом, а
  -- триггер очереди срабатывает только на «удалено у всех», не на каскад.
  insert into chat_media_trash (bucket, path)
  select 'chat-media', m.media ->> 'path'
  from chat_messages m
  where m.sender_id = me and m.media ? 'path'
  on conflict do nothing;

  -- Всё в папке с моим id: аватар и видеоаватар, фото публикаций и
  -- маршрутов, файлы помощника.
  insert into chat_media_trash (bucket, path)
  select o.bucket_id, o.name
  from storage.objects o
  where o.bucket_id in ('avatars', 'post-media', 'route-photos', 'assistant')
    and o.name like me::text || '/%'
  on conflict do nothing;

  delete from auth.users where id = me;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
