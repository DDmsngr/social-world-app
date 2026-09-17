-- Раздача APK для автообновления в приложении.
--
-- Бакет публичный на чтение — сам файл обновления не секрет. Политики на
-- запись здесь нет вообще: без insert-политики запись возможна только
-- service_role ключом (он RLS обходит), поэтому кладёт файлы туда исключительно
-- CI после сборки релиза — ни анон, ни обычный пользователь подменить APK
-- не может.

insert into storage.buckets (id, name, public)
values ('app-releases', 'app-releases', true)
on conflict (id) do nothing;

create policy "обновления читают все"
  on storage.objects for select
  using (bucket_id = 'app-releases');
