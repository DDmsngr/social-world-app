-- Уведомление о комментарии ведёт к самому комментарию (просьба Алексея
-- 15.10.2026): раньше в уведомлении был только пост, и человек искал ответ
-- в ветке глазами.
--
-- notifications.comment_id — какой комментарий показать и подсветить.
-- add_notification получает его седьмым параметром; шестипараметровая
-- версия остаётся для остальных вызовов. Если непрочитанное уведомление
-- от того же человека по тому же посту уже есть, оно не дублируется, а
-- переводится на свежий комментарий.

alter table notifications add column comment_id uuid references post_comments on delete set null;

create function add_notification(
  in_recipient uuid,
  in_actor uuid,
  in_kind text,
  in_target_type text,
  in_target uuid,
  in_title text,
  in_comment uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare
  existing uuid;
begin
  if in_recipient is null or in_recipient = in_actor then return; end if;
  if in_actor is not null and is_hidden_between(in_recipient, in_actor) then return; end if;
  if not notify_enabled(in_recipient, notification_category(in_kind)) then return; end if;

  select n.id into existing from notifications n
  where n.recipient_id = in_recipient
    and n.actor_id is not distinct from in_actor
    and n.kind = in_kind
    and n.target_id = in_target
    and n.read_at is null
  limit 1;
  if existing is not null then
    if in_comment is not null then
      update notifications
      set comment_id = in_comment, title = left(in_title, 120), created_at = now()
      where id = existing;
    end if;
    return;
  end if;

  insert into notifications (recipient_id, actor_id, kind, target_type, target_id, title, comment_id)
  values (in_recipient, in_actor, in_kind, in_target_type, in_target, left(in_title, 120), in_comment);
end;
$$;

revoke all on function add_notification(uuid, uuid, text, text, uuid, text, uuid) from public, anon, authenticated;

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
    perform add_notification(parent_author, new.author_id, 'reply', 'post', new.post_id, shown, new.id);
  end if;
  if parent_author is distinct from post_author then
    perform add_notification(post_author, new.author_id, 'comment', 'post', new.post_id, shown, new.id);
  end if;
  return new;
end;
$$;

-- Тип результата меняется (новая колонка), поэтому пересоздание.
drop function my_notifications(integer);

create function my_notifications(in_limit integer default 50)
returns table (
  id           uuid,
  kind         text,
  actor_id     uuid,
  actor_name   text,
  actor_avatar text,
  target_type  text,
  target_id    uuid,
  title        text,
  created_at   timestamptz,
  read_at      timestamptz,
  comment_id   uuid
)
language sql stable security definer set search_path = public as $$
  select n.id, n.kind, n.actor_id, p.display_name, p.avatar_url,
         n.target_type, n.target_id, n.title, n.created_at, n.read_at, n.comment_id
  from notifications n
  left join profiles p on p.id = n.actor_id
  where n.recipient_id = auth.uid()
    and (n.actor_id is null or not is_hidden_between(auth.uid(), n.actor_id))
  order by n.created_at desc
  limit least(in_limit, 100);
$$;

revoke all on function my_notifications(integer) from public, anon;
grant execute on function my_notifications(integer) to authenticated;
