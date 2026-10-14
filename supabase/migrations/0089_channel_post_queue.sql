-- Очередь отложенных постов в каналы.
--
-- Посты (текст в Markdown, картинка — ссылкой внутри текста) кладутся заранее
-- с временем выхода; раз в минуту pg_cron выкладывает те, чьё время пришло.
-- Не зависит ни от чьей сессии, ни от GitHub Actions. Первое применение —
-- ежедневные новости разработки в @chawo в 20:00 по Москве.
--
-- Писать в очередь может только service_role (tools/channel-queue/enqueue.ps1).
-- Опоздание пропускает не больше суток: застарелый пост не выходит.

create table channel_post_queue (
  id           uuid primary key default gen_random_uuid(),
  handle       text not null,
  source_ref   text not null unique,
  body         text not null check (char_length(body) between 1 and 4000),
  publish_at   timestamptz not null,
  status       text not null default 'queued' check (status in ('queued', 'published', 'error', 'skipped')),
  published_at timestamptz,
  error        text,
  created_at   timestamptz not null default now()
);

create index channel_post_queue_due_idx on channel_post_queue (publish_at) where status = 'queued';

alter table channel_post_queue enable row level security;
revoke all on channel_post_queue from public, anon, authenticated;
grant all on channel_post_queue to service_role;

create function channel_queue_release() returns integer
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  item record;
  released integer := 0;
begin
  for item in
    select * from channel_post_queue
    where status = 'queued' and publish_at <= now()
    order by publish_at
    for update skip locked
  loop
    -- Опоздали больше чем на сутки (сервер лежал): не выкладываем вчерашнее.
    if item.publish_at < now() - interval '1 day' then
      update channel_post_queue set status = 'skipped' where id = item.id;
      continue;
    end if;
    begin
      perform channel_feed_post(item.handle, item.source_ref, 'text', item.body, null);
      update channel_post_queue set status = 'published', published_at = now() where id = item.id;
      released := released + 1;
    exception when others then
      update channel_post_queue set status = 'error', error = left(sqlerrm, 300) where id = item.id;
    end;
  end loop;
  return released;
end;
$$;

revoke all on function channel_queue_release() from public, anon, authenticated;

select cron.schedule('channel-post-queue', '* * * * *', 'select public.channel_queue_release()');
