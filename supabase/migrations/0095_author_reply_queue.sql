-- Ответы виртуальных авторов (0090) на комментарии. Решение Алексея 15.10.2026:
-- авторы отвечают людям осознанно, по своему посту и источнику. До релиза
-- ответы пишет редакция (раз в сутки, вместе с ночным разбором багов), потом
-- то же самое будет делать модель YandexGPT на сервере.
--
-- Комментарий человека попадает в очередь, если он написан под постом
-- автора или в ответ на комментарий автора. Комментарии самих авторов в
-- очередь не попадают: авторы не переписываются друг с другом.
-- Ответ публикуется обычным комментарием-ответом от имени автора
-- (author_reply_post), отказ отвечать — author_reply_skip с причиной.

create table author_reply_queue (
  comment_id uuid primary key references post_comments on delete cascade,
  author_id  uuid not null references bot_authors (profile_id) on delete cascade,
  post_id    uuid not null references posts on delete cascade,
  status     text not null default 'pending' check (status in ('pending', 'answered', 'skipped')),
  reply_id   uuid references post_comments on delete set null,
  note       text,
  -- кто ответил: 'editor' (редакция вручную) или 'yandexgpt'
  answered_by text,
  created_at timestamptz not null default now(),
  handled_at timestamptz
);

create index author_reply_queue_pending_idx on author_reply_queue (created_at) where status = 'pending';

alter table author_reply_queue enable row level security;
revoke all on author_reply_queue from public, anon, authenticated;
grant all on author_reply_queue to service_role;

create function author_reply_enqueue() returns trigger
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  target uuid;
begin
  if exists (select 1 from bot_authors where profile_id = new.author_id) then
    return new;
  end if;
  if new.parent_id is not null then
    select c.author_id into target
    from post_comments c join bot_authors b on b.profile_id = c.author_id
    where c.id = new.parent_id;
  end if;
  if target is null then
    select p.author_id into target
    from posts p join bot_authors b on b.profile_id = p.author_id
    where p.id = new.post_id;
  end if;
  if target is not null then
    insert into author_reply_queue (comment_id, author_id, post_id)
    values (new.id, target, new.post_id)
    on conflict do nothing;
  end if;
  return new;
end;
$$;

revoke all on function author_reply_enqueue() from public, anon, authenticated;

create trigger author_reply_enqueue after insert on post_comments
  for each row execute function author_reply_enqueue();

-- Опубликовать ответ. Комментарий должен быть ещё живым (не удалён и не
-- скрыт модерацией), иначе ответ не нужен — строка уходит в skipped.
create function author_reply_post(p_comment uuid, p_body text, p_by text default 'editor')
returns uuid
language plpgsql security definer set search_path = public set row_security = off as $$
declare
  item author_reply_queue;
  alive boolean;
  new_id uuid;
begin
  select * into item from author_reply_queue where comment_id = p_comment for update;
  if not found then
    raise exception 'author_reply: комментария нет в очереди';
  end if;
  if item.status <> 'pending' then
    raise exception 'author_reply: уже обработан (%)', item.status;
  end if;
  select deleted_at is null and status <> 'blocked' into alive from post_comments where id = p_comment;
  if not coalesce(alive, false) then
    update author_reply_queue set status = 'skipped', note = 'комментарий удалён', handled_at = now()
    where comment_id = p_comment;
    return null;
  end if;
  insert into post_comments (post_id, parent_id, author_id, body)
  values (item.post_id, p_comment, item.author_id, p_body)
  returning id into new_id;
  update author_reply_queue
  set status = 'answered', reply_id = new_id, answered_by = p_by, handled_at = now()
  where comment_id = p_comment;
  return new_id;
end;
$$;

create function author_reply_skip(p_comment uuid, p_note text, p_by text default 'editor')
returns void
language sql security definer set search_path = public set row_security = off as $$
  update author_reply_queue
  set status = 'skipped', note = left(p_note, 300), answered_by = p_by, handled_at = now()
  where comment_id = p_comment and status = 'pending';
$$;

revoke all on function author_reply_post(uuid, text, text) from public, anon, authenticated;
revoke all on function author_reply_skip(uuid, text, text) from public, anon, authenticated;
grant execute on function author_reply_post(uuid, text, text) to service_role;
grant execute on function author_reply_skip(uuid, text, text) to service_role;

-- Комментарии людей под постами авторов, оставленные до этой миграции.
insert into author_reply_queue (comment_id, author_id, post_id, created_at)
select c.id, p.author_id, c.post_id, c.created_at
from post_comments c
join posts p on p.id = c.post_id
join bot_authors b on b.profile_id = p.author_id
where c.deleted_at is null
  and not exists (select 1 from bot_authors x where x.profile_id = c.author_id)
on conflict do nothing;
