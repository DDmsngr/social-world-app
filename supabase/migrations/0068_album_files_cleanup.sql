-- Альбом (несколько фото в одном сообщении группы): файлы лежат в
-- media -> 'album' (массив с path). Когда сообщение удалено у всех, в очередь
-- на стирание шли только media ->> 'path', а файлы альбома оставались в
-- хранилище навсегда. Теперь в очередь идут все.

create or replace function trg_chat_media_trash_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.deleted_at is null and new.deleted_at is not null
     and old.media ? 'path' then
    insert into chat_media_trash (path) values (old.media ->> 'path')
    on conflict do nothing;

    if jsonb_typeof(old.media -> 'album') = 'array' then
      insert into chat_media_trash (path)
      select a ->> 'path'
      from jsonb_array_elements(old.media -> 'album') a
      where a ? 'path'
      on conflict do nothing;
    end if;
  end if;
  return new;
end;
$$;
