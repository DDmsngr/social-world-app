-- Упоминания @ник в бликах. В постах и комментариях они работают с 0070;
-- блик — новый вид цели уведомления (target_type 'story'), тап по уведомлению
-- открывает сам блик.
--
-- Уведомление получает только тот, кому блик виден: публичный — любой,
-- «для подписчиков» — подписчик автора. Скрытые друг от друга (блокировка) —
-- нет.

alter table notifications drop constraint notifications_target_type_check;
alter table notifications add constraint notifications_target_type_check check (target_type in (
  'profile', 'post', 'event', 'place', 'route', 'quest', 'need', 'points', 'chat', 'story'
));

create function trg_mentions_story() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uname text;
  rid uuid;
begin
  if coalesce(new.body, '') !~ '@[A-Za-z0-9_]{3,20}' then return new; end if;

  for uname in
    select distinct lower(m[1])
    from regexp_matches(new.body, '(?:^|[^A-Za-z0-9_@])@([A-Za-z0-9_]{3,20})', 'g') as m
    limit 10
  loop
    select id into rid from profiles where username = uname and status <> 'blocked';
    continue when rid is null or rid = new.author_id;
    continue when is_hidden_between(rid, new.author_id);
    continue when new.visibility = 'followers' and not exists (
      select 1 from follows f
      where f.follower_id = rid and f.target_type = 'profile' and f.target_id = new.author_id
    );

    perform add_notification(rid, new.author_id, 'mention', 'story', new.id,
                             left(btrim(new.body), 120));
  end loop;
  return new;
end;
$$;

revoke all on function trg_mentions_story() from public, anon, authenticated;

create trigger mentions_on_story after insert on stories
  for each row execute function trg_mentions_story();
