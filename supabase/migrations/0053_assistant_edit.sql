-- 0053: в «Помощнике» своё сообщение можно исправить или удалить, пока оно
-- «ждёт» — Помощник его ещё не забрал (handled_at is null). После того как
-- забрал, текст уже в работе и меняться не должен.

grant update (body) on assistant_messages to authenticated;
grant delete on assistant_messages to authenticated;

create policy "помощник: владелец правит ждущее" on assistant_messages
  for update to authenticated
  using (is_assistant_owner() and from_user and handled_at is null)
  with check (is_assistant_owner() and from_user and handled_at is null);

create policy "помощник: владелец удаляет ждущее" on assistant_messages
  for delete to authenticated
  using (is_assistant_owner() and from_user and handled_at is null);
