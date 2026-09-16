-- Лента событий: участие и запрос, который отдаёт событие сразу с автором,
-- местом и счётчиком участников — по образцу city_feed из 0002_feed.sql.

-- Раньше у events не было ни delete-политики, ни способа записаться удобно
-- одним запросом — таблицы появились в 0001, но приложение на них не жило.

create policy "событие удаляет автор"
  on events for delete to authenticated using (auth.uid() = author_id);

-- Участие получает автор события, а не тот, кто записался — тот же принцип,
-- что и с лайками: самому себе очки не начисляются.
create function apply_event_join_score() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  target_author uuid;
  delta integer;
begin
  if tg_op = 'INSERT' then
    select author_id into target_author from events where id = new.event_id;
    delta := 1;
    if target_author is null or target_author = new.profile_id then
      return new;
    end if;
  else
    select author_id into target_author from events where id = old.event_id;
    delta := -1;
    if target_author is null or target_author = old.profile_id then
      return old;
    end if;
  end if;

  insert into score_events (profile_id, reason, delta)
  values (target_author, 'event_join', delta);

  return case tg_op when 'INSERT' then new else old end;
end;
$$;

create trigger on_event_join
  after insert or delete on event_participants
  for each row execute function apply_event_join_score();

create function city_events(in_limit integer default 50)
returns table (
  id               uuid,
  author_id        uuid,
  author_name      text,
  avatar_url       text,
  title            text,
  description      text,
  starts_at        timestamptz,
  ends_at          timestamptz,
  place_title      text,
  cover_url        text,
  created_at       timestamptz,
  participant_count bigint,
  joined_by_me     boolean
)
language sql stable security definer set search_path = public as $$
  select e.id,
         e.author_id,
         pr.display_name,
         pr.avatar_url,
         e.title,
         e.description,
         e.starts_at,
         e.ends_at,
         pl.title,
         e.cover_url,
         e.created_at,
         count(ep.profile_id),
         bool_or(ep.profile_id = auth.uid())
  from events e
  join profiles pr on pr.id = e.author_id
  left join places pl on pl.id = e.place_id
  left join event_participants ep on ep.event_id = e.id
  where e.status = 'active'
    and pr.status <> 'blocked'
    and not exists (
      select 1 from reports r
      where r.reporter_id = auth.uid()
        and r.status in ('new', 'in_review')
        and (
          (r.target = 'event' and r.target_id = e.id) or
          (r.target = 'profile' and r.target_id = e.author_id)
        )
    )
  group by e.id, pr.display_name, pr.avatar_url, pl.title
  order by e.starts_at asc
  limit least(in_limit, 100);
$$;

revoke all on function city_events from public;
grant execute on function city_events to authenticated;
