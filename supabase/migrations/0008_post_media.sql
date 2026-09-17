-- Фото и видео постов.
--
-- Колонка `posts.media_urls` есть с первой миграции, но класть файлы было
-- некуда: бакет был только у фотографий маршрута. Правила те же, что и там —
-- читают все, пишет человек только в свою папку `<uid>/`.

insert into storage.buckets (id, name, public)
values ('post-media', 'post-media', true)
on conflict (id) do nothing;

create policy "медиа постов читают все"
  on storage.objects for select
  using (bucket_id = 'post-media');

create policy "загружаю медиа поста только в свою папку"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "удаляю только своё медиа поста"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
