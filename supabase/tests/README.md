# SQL-проверки

`chat_delete_and_scheduled.sql` — проверки миграций 0033 (удаление сообщений) и
0034 (ответы, «без звука», присутствие, отложенные сообщения): права, RLS,
ограничения и выпуск отложенных.

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres supabase/tests/run.sh
```

`run.sh` создаёт временную базу, строит заглушки Supabase (`auth`, `storage`,
роли, `profiles`), накатывает реальные миграции чата и прогоняет проверки.
Успех — строка `ALL OK`. pg_cron там нет — проверяется сама функция выпуска
`release_scheduled_chat_messages()`, расписание на сервере создаёт миграция.
