-- Очередь постов виртуальных авторов (0090): те же правила, что у очереди
-- каналов (0089), но на выходе обычный пост в ленте от имени автора.
--
-- Пост кладут заранее с временем выхода (service_role), pg_cron раз в минуту
-- выкладывает наступившие. Автор должен быть в bot_authors: от имени живых
-- людей эта очередь публиковать не умеет. Опоздание больше суток — пропуск.

create table author_post_queue (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references bot_authors (profile_id) on delete cascade,
  source_ref   text not null unique,
  body         text not null check (char_length(body) between 1 and 5000),
  media_urls   text[] not null default '{}',
  publish_at   timestamptz not null,
  status       text not null default 'queued' check (status in ('queued', 'published', 'error', 'skipped')),
  post_id      uuid,
  published_at timestamptz,
  error        text,
  created_at   timestamptz not null default now()
);

create index author_post_queue_due_idx on author_post_queue (publish_at) where status = 'queued';

alter table author_post_queue enable row level security;
revoke all on author_post_queue from public, anon, authenticated;
grant all on author_post_queue to service_role;

create function author_queue_release() returns integer
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  item record;
  new_post uuid;
  released integer := 0;
begin
  for item in
    select * from author_post_queue
    where status = 'queued' and publish_at <= now()
    order by publish_at
    for update skip locked
  loop
    if item.publish_at < now() - interval '1 day' then
      update author_post_queue set status = 'skipped' where id = item.id;
      continue;
    end if;
    begin
      insert into posts (author_id, kind, post_type, body, body_format, media_urls, visibility, show_geo)
      values (item.author_id,
              case when cardinality(item.media_urls) > 0 then 'photo'::post_kind else 'text'::post_kind end,
              'moment', item.body, 'plain', item.media_urls, 'public', false)
      returning id into new_post;
      update author_post_queue set status = 'published', post_id = new_post, published_at = now()
      where id = item.id;
      released := released + 1;
    exception when others then
      update author_post_queue set status = 'error', error = left(sqlerrm, 300) where id = item.id;
    end;
  end loop;
  return released;
end;
$$;

revoke all on function author_queue_release() from public, anon, authenticated;

select cron.schedule('author-post-queue', '* * * * *', 'select public.author_queue_release()');
