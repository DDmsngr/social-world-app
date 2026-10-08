-- Удаление аккаунта самим человеком (152-ФЗ: право на удаление ПД).
-- Всё, что связано с профилем, уходит каскадом от auth.users (проверено по
-- pg_constraint: у profiles и всех таблиц профиля on delete cascade).
-- Личные чаты остаются у собеседника, но без сообщений удалившегося.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- Аккаунт команды (дашборд) удаляется вручную: там задачи и переписка команды.
  if exists (select 1 from public.ws_members where user_id = me) then
    raise exception 'team account: delete via support' using errcode = '42501';
  end if;
  delete from auth.users where id = me;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
