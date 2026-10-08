-- Фото и гифки в комментариях (колонка media_urls заведена в 0009, а прикрепить
-- было нечем). Комментарий может состоять из одной картинки без текста, но не
-- может быть пустым совсем; картинок не больше 4 на комментарий.

do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.post_comments'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%length(body)%'
  loop
    execute format('alter table post_comments drop constraint %I', c.conname);
  end loop;
end $$;

alter table post_comments alter column body set default '';

alter table post_comments
  add constraint post_comments_content_check check (
    char_length(body) <= 2000
    and (char_length(body) > 0 or cardinality(media_urls) > 0)
  ),
  add constraint post_comments_media_limit check (cardinality(media_urls) <= 4);

-- В уведомлении об ответе у комментария без текста — «фото», а не пустые
-- кавычки.
create or replace function trg_notify_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  post_author uuid;
  parent_author uuid;
  shown text := coalesce(nullif(btrim(new.body), ''), '📷 фото');
begin
  select author_id into post_author from posts where id = new.post_id;
  if new.parent_id is not null then
    select author_id into parent_author from post_comments where id = new.parent_id;
    perform add_notification(parent_author, new.author_id, 'reply', 'post', new.post_id, shown);
  end if;
  if parent_author is distinct from post_author then
    perform add_notification(post_author, new.author_id, 'comment', 'post', new.post_id, shown);
  end if;
  return new;
end;
$$;
