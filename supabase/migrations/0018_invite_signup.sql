-- Регистрация по токену приглашения, без писем.
--
-- Почему: на сервере SMTP-заглушка (supabase-mail / fake_sender), письма
-- подтверждения не уходят, а ENABLE_EMAIL_AUTOCONFIRM=false — обычный signUp
-- по приглашению падает с «Error sending confirmation email».
--
-- Токен приглашения (128 бит, хранится хешем, живёт 14 дней) админ передаёт
-- человеку лично — он и подтверждает владение почтой. Функция создаёт уже
-- подтверждённый аккаунт ровно на email из приглашения. Поведение регистрации
-- в самом приложении не меняется: включать autoconfirm глобально не нужно.
--
-- Принять приглашение (привязать аккаунт к ws_members) по-прежнему делает
-- ws_accept_invitation после входа.

create function ws_register_via_invitation(p_token text, p_password text) returns void
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  i ws_invitations;
  v_user uuid := gen_random_uuid();
begin
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'пароль не короче 8 символов';
  end if;

  select * into i from ws_invitations
  where token_hash = sha256(convert_to(p_token, 'utf8'))
  for update;
  if i.id is null or i.status <> 'invited' or i.expires_at <= now() then
    raise exception 'приглашение недействительно или просрочено';
  end if;

  if exists (select 1 from auth.users where lower(email) = lower(i.email)) then
    raise exception 'аккаунт с этим email уже есть — войдите с его паролем';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values (
    '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
    lower(i.email), extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user, v_user::text, 'email',
    jsonb_build_object('sub', v_user::text, 'email', lower(i.email), 'email_verified', true),
    now(), now(), now()
  );
end
$$;

grant execute on function ws_register_via_invitation to anon, authenticated;

-- ── починка 0017: принятие приглашения упиралось в ws_members_guard ─────────
-- Триггер запрещал переводить invited → active всем, у кого auth.uid() не пуст,
-- в том числе самой ws_accept_invitation (она security definer, но uid остаётся
-- вызывающего). Теперь accept на время своей транзакции поднимает флаг.
-- Клиент выставить GUC в одной транзакции с UPDATE через REST не может.

create or replace function ws_members_guard() returns trigger
language plpgsql security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is null then return new; end if;  -- сервисный доступ
  if current_setting('ws.accepting', true) = '1' then return new; end if;
  if new.role is distinct from old.role or new.status is distinct from old.status then
    if old.user_id = auth.uid() then
      raise exception 'свою роль и статус менять нельзя';
    end if;
    if old.role = 'owner' or new.role = 'owner' then
      raise exception 'роль owner не меняется через интерфейс';
    end if;
    if new.role = 'admin' and ws_role(old.workspace_id) <> 'owner' then
      raise exception 'администраторов назначает только owner';
    end if;
    if old.status = 'invited' and new.status <> 'invited' then
      raise exception 'приглашённый становится активным только по токену';
    end if;
  end if;
  return new;
end
$$;

create or replace function ws_accept_invitation(p_token text) returns uuid
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
  i ws_invitations;
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then raise exception 'нужно войти'; end if;
  select * into i from ws_invitations
  where token_hash = sha256(convert_to(p_token, 'utf8')) for update;
  if i.id is null or i.status <> 'invited' or i.expires_at <= now() then
    raise exception 'приглашение недействительно или просрочено';
  end if;
  if lower(i.email) <> v_email then
    raise exception 'приглашение выписано на другой email';
  end if;
  if exists (select 1 from ws_members where workspace_id = i.workspace_id and user_id = auth.uid()) then
    raise exception 'вы уже участник этого workspace';
  end if;

  perform set_config('ws.accepting', '1', true);
  update ws_members
     set user_id = auth.uid(), status = 'active', joined_at = now(), last_seen = now()
   where id = i.member_id;
  perform set_config('ws.accepting', '', true);
  update ws_invitations set status = 'accepted', accepted_at = now() where id = i.id;

  perform ws_log(i.workspace_id, null, 'member', i.member_id, 'member.joined',
                 jsonb_build_object('name', (select name from ws_members where id = i.member_id)));
  return i.workspace_id;
end
$$;
