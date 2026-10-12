-- Скрытый бонус Activity Points: за каждый пятый лайк на публикации автора ему
-- начисляется 1 балл на следующий день. Пользователям о правиле не сообщается.
--
-- Считаем лайки на посты автора от других людей (свои не в счёт) по сутки
-- включительно до полуночи по Москве; ночью задача доначисляет разницу между
-- «сколько пятёрок набралось» и «сколько уже начислено». Снятый лайк баллы не
-- отбирает и повторно пятёрку не даёт: считается число лайков, а не нажатия.
-- Старые лайки задним числом не оплачиваются: счёт идёт с момента миграции.

create table if not exists like_bonus_progress (
  profile_id uuid primary key references profiles on delete cascade,
  awarded    integer not null default 0
);

alter table like_bonus_progress enable row level security;
-- Политик нет намеренно: читает и пишет только функция ниже.

-- Начальные значения: уже набранные пятёрки считаем начисленными.
insert into like_bonus_progress (profile_id, awarded)
select po.author_id, count(*)::int / 5
from post_likes pl
join posts po on po.id = pl.post_id
where pl.profile_id <> po.author_id
group by po.author_id
having count(*) >= 5
on conflict (profile_id) do nothing;

create or replace function like_bonus_tick() returns integer
language plpgsql security definer set search_path = public as $$
declare
  cutoff timestamptz := date_trunc('day', now() at time zone 'Europe/Moscow') at time zone 'Europe/Moscow';
  granted integer := 0;
  r record;
begin
  for r in
    select c.author_id, c.n / 5 as milestones, coalesce(p.awarded, 0) as awarded
    from (
      select po.author_id, count(*)::int as n
      from post_likes pl
      join posts po on po.id = pl.post_id
      where pl.profile_id <> po.author_id and pl.created_at < cutoff
      group by po.author_id
    ) c
    left join like_bonus_progress p on p.profile_id = c.author_id
    where c.n / 5 > coalesce(p.awarded, 0)
  loop
    insert into score_events (profile_id, reason, delta)
    values (r.author_id, 'like_bonus', r.milestones - r.awarded);

    insert into like_bonus_progress (profile_id, awarded)
    values (r.author_id, r.milestones)
    on conflict (profile_id) do update set awarded = excluded.awarded;

    granted := granted + (r.milestones - r.awarded);
  end loop;
  return granted;
end $$;

revoke all on function like_bonus_tick from public;

-- Каждую ночь в 00:05 по Москве (21:05 UTC).
select cron.schedule('like-bonus-tick', '5 21 * * *', 'select public.like_bonus_tick()')
where not exists (select 1 from cron.job where jobname = 'like-bonus-tick');
