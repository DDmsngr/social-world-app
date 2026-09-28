-- Вторая часть находки 27–28.09 — отдельный, более серьёзный случай той же
-- болезни. 0027 закрыл роль anon там, где её впустил кастомный
-- `alter default privileges ... to anon` self-hosted Supabase. Но у функций
-- Team Workspace (0017–0021) дыра ДРУГАЯ и более старая: почти ни одна из
-- них никогда не получала `revoke ... from public` вообще — а ванильный
-- Postgres сам, безо всякого Supabase, даёт `execute` роли PUBLIC при
-- каждом `create function`, если явно не отозвать. PUBLIC — это не «анон
-- и всё», это буквально любая роль в базе, включая ту же authenticated, а
-- «revoke execute … from anon» из 0027 такую запись не трогает вовсе:
-- анонимный запрос к панели команды (ws_claim_task, ws_create_group,
-- ws_import_tasks, ws_mark_read, ws_open_direct, ws_role, ws_is_member,
-- ws_unread_counts и ещё два десятка) до сих пор проходил бы без единого
-- исключения — ровно то же, чем мы занимались вчера, только другой рычаг.
--
-- Проверено: у service_role есть свой отдельный grant (тот же слой Supabase,
-- что и у anon/authenticated) — «revoke … from public» его не заденет,
-- значит CI и Edge Functions не пострадают.
--
-- Функции ws_invitation_preview и ws_register_via_invitation не трогаем —
-- у них уже есть собственный явный grant и authenticated, и anon (вход по
-- приглашению — по определению до входа в систему).
--
-- Ниже — явный grant для authenticated на каждую функцию, что реально
-- дёргает панель напрямую (список получен запросом к pg_proc 27.09, до
-- этой миграции). Триггерные функции (ws_attachments_before/after,
-- ws_comments_before/after, ws_members_guard, ws_messages_before,
-- ws_tasks_before/after/num) в список тоже включены для полноты и на
-- случай будущего прямого вызова — самим триггерам чужой EXECUTE не нужен:
-- Postgres не проверяет привилегию вызывающей роли на функцию-триггер,
-- она срабатывает независимо от прав того, кто выполнил INSERT/UPDATE.

revoke execute on all functions in schema public from public;

grant execute on function ws_accept_invitation(p_token text) to authenticated;
grant execute on function ws_attachments_after() to authenticated;
grant execute on function ws_attachments_before() to authenticated;
grant execute on function ws_can_read_conv(p_conv uuid) to authenticated;
grant execute on function ws_claim_task(p_task uuid) to authenticated;
grant execute on function ws_comments_after() to authenticated;
grant execute on function ws_comments_before() to authenticated;
grant execute on function ws_conv_members(p_conv uuid) to authenticated;
grant execute on function ws_create_group(p_ws uuid, p_name text, p_members uuid[]) to authenticated;
grant execute on function ws_group_add_members(p_conv uuid, p_members uuid[]) to authenticated;
grant execute on function ws_import_tasks(p_project uuid, p_tasks jsonb) to authenticated;
grant execute on function ws_invite_member(p_ws uuid, p_name text, p_email text, p_role text, p_message text) to authenticated;
grant execute on function ws_is_admin(p_ws uuid) to authenticated;
grant execute on function ws_is_member(p_ws uuid) to authenticated;
grant execute on function ws_mark_read(p_conv uuid) to authenticated;
grant execute on function ws_members_guard() to authenticated;
grant execute on function ws_messages_before() to authenticated;
grant execute on function ws_open_direct(p_ws uuid, p_other uuid) to authenticated;
grant execute on function ws_reissue_invitation(p_member uuid) to authenticated;
grant execute on function ws_release_task(p_task uuid) to authenticated;
grant execute on function ws_role(p_ws uuid) to authenticated;
grant execute on function ws_sync_overdue(p_ws uuid) to authenticated;
grant execute on function ws_task_ws(p_task uuid) to authenticated;
grant execute on function ws_tasks_after() to authenticated;
grant execute on function ws_tasks_before() to authenticated;
grant execute on function ws_tasks_num() to authenticated;
grant execute on function ws_touch(p_ws uuid) to authenticated;
grant execute on function ws_unread_counts(p_ws uuid) to authenticated;

-- На будущее у той же ловушки: если функцию создаёт не роль postgres,
-- PUBLIC-grant Postgres выставляет всё равно (это его собственное поведение,
-- не Supabase), так что чинить это придётся руками на каждую новую функцию
-- явным «revoke ... from public» сразу в миграции — alter default privileges
-- эту часть не закрывает никаким способом.
