-- Закрытие замечаний проверки безопасности AP (0099) и амбассадоров (0100).
--
--  * Лайк снят или комментарий удалён — начисление отменяется сразу, а не через
--    сутки: иначе недоброжелатель мог лайкнуть пятьдесят постов соперника,
--    снять лайки и на сутки забить ему дневной лимит. Повторно получить AP за
--    тот же лайк нельзя: отменённая строка остаётся и держит уникальный индекс.
--  * Откат подтверждённых AP у накрутчика: по получателю или по тем, чьи
--    действия принесли баллы (фейки). Минус идёт в тот город и в тот сезон,
--    где были начислены баллы, иначе рейтинг прошлого сезона не очистился бы.
--  * Автор события не может править его строку (время окончания, статус):
--    приложение события только создаёт и удаляет.

-- ── отмена начислений при снятии лайка и удалении комментария ───────────────

create function activity_cancel_like() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update activity_awards set status = 'cancelled', settled_at = now()
  where code = 'post_like' and source_id = old.post_id and actor_id = old.profile_id
    and status = 'pending';
  return old;
end $$;

create trigger activity_cancel_like after delete on post_likes
  for each row execute function activity_cancel_like();

-- Комментарий считается один раз с человека на пост: отменяем, только если
-- у этого человека под постом не осталось других живых комментариев.
create function activity_cancel_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rec post_comments := case tg_op when 'DELETE' then old else new end;
begin
  if tg_op = 'UPDATE' and not (
       (new.deleted_at is not null and old.deleted_at is null)
       or (new.status = 'blocked' and old.status <> 'blocked')) then
    return new;
  end if;
  if exists (select 1 from post_comments c
             where c.post_id = rec.post_id and c.author_id = rec.author_id and c.id <> rec.id
               and c.deleted_at is null and c.status <> 'blocked') then
    return rec;
  end if;
  update activity_awards set status = 'cancelled', settled_at = now()
  where code = 'post_comment' and source_id = rec.post_id and actor_id = rec.author_id
    and status = 'pending';
  return rec;
end $$;

create trigger activity_cancel_comment after update of deleted_at, status or delete on post_comments
  for each row execute function activity_cancel_comment();

-- ── откат подтверждённых AP ─────────────────────────────────────────────────

alter table activity_awards drop constraint activity_awards_status_check;
alter table activity_awards add constraint activity_awards_status_check
  check (status in ('pending', 'confirmed', 'cancelled', 'reversed'));

-- Общий откат: все подтверждённые начисления, подходящие под условие.
create function activity_reverse_where(in_recipient uuid, in_actor uuid, in_since timestamptz)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  a activity_awards;
  n integer := 0;
begin
  if in_recipient is null and in_actor is null then
    raise exception 'recipient_or_actor_required';
  end if;
  for a in
    select * from activity_awards
    where status = 'confirmed'
      and (in_recipient is null or profile_id = in_recipient)
      and (in_actor is null or actor_id = in_actor)
      and coalesce(settled_at, created_at) >= coalesce(in_since, '-infinity')
    for update
  loop
    -- Минус датируется моментом подтверждения: так он попадает в тот же сезон.
    insert into score_events (profile_id, reason, delta, city, created_at)
    values (a.profile_id, 'activity_reversal', -a.amount, a.city, coalesce(a.settled_at, a.created_at));
    update activity_awards set status = 'reversed', settled_at = now() where id = a.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Снять всё, что получил человек (накрутка у получателя).
create function activity_reverse_recipient(in_profile uuid, in_since timestamptz default null)
returns integer
language sql security definer set search_path = public as $$
  select activity_reverse_where(in_profile, null, in_since)
$$;

-- Снять всё, что принесли действия человека (фейковый аккаунт): у любых получателей.
create function activity_reverse_actor(in_actor uuid, in_since timestamptz default null)
returns integer
language sql security definer set search_path = public as $$
  select activity_reverse_where(null, in_actor, in_since)
$$;

revoke all on function activity_cancel_like() from public, anon, authenticated;
revoke all on function activity_cancel_comment() from public, anon, authenticated;
revoke all on function activity_reverse_where(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function activity_reverse_recipient(uuid, timestamptz) from public, anon, authenticated;
revoke all on function activity_reverse_actor(uuid, timestamptz) from public, anon, authenticated;

-- ── события: автор не правит строку ─────────────────────────────────────────

revoke update on events from authenticated;
