-- Свежесть точки присутствия должен ставить сервер, а не клиент.
--
-- `nearby_profiles` (0001) прячет точки старше двух часов по `updated_at`, но
-- у колонки только `default now()` — он срабатывает при вставке и молчит при
-- обновлении. Без этого триггера upsert второй и далее раз оставлял бы старое
-- время, и человек исчезал бы с карты через два часа, продолжая слать точку.
--
-- Клиент шлёт `updated_at` сам (см. SupabaseDiscoverRepository.publishPresence)
-- — это работает, пока миграция не применена. Но полагаться на часы телефона
-- нельзя: сбитое на пару часов время сделает человека либо вечно свежим, либо
-- невидимым сразу. Триггер перекрывает присланное значение своим now().

create or replace function touch_location_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger locations_touch_updated_at
  before insert or update on locations
  for each row execute function touch_location_updated_at();
