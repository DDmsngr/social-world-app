-- Проверки магазина стикеров (0078): каталог, коллекция, права, архив,
-- запрет удаления, паки новым пользователям, запись в бакет.
--
-- Запускается на базе с накатанной 0078 и опубликованными паками (в том
-- числе на боевой): всё идёт в одной транзакции и откатывается.
--   psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f stickers.sql
-- Успех — строка «ALL OK»; провал — исключение с названием проверки.

begin;

create function pg_temp.as_user(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

-- Два тестовых пользователя: профили появляются триггером на auth.users.
insert into auth.users (id, email, aud, role)
values ('5717c3e5-0000-4000-8000-00000000000a', 'sticker-test-a@chawo.local', 'authenticated', 'authenticated'),
       ('5717c3e5-0000-4000-8000-00000000000b', 'sticker-test-b@chawo.local', 'authenticated', 'authenticated');
insert into profiles (id) values
  ('5717c3e5-0000-4000-8000-00000000000a'), ('5717c3e5-0000-4000-8000-00000000000b')
on conflict do nothing;

do $$
declare n int; ids text[];
begin
  -- Новому пользователю — паки по умолчанию (basic, chao), и только они.
  select array_agg(pack_id order by pack_id) into ids from user_sticker_packs
  where profile_id = '5717c3e5-0000-4000-8000-00000000000a';
  if ids is distinct from (select array_agg(id order by id) from sticker_packs where is_default and status = 'published') then
    raise exception 'FAIL default packs: %', ids;
  end if;
end $$;

-- ── каталог ─────────────────────────────────────────────────────────────────
select pg_temp.as_user('5717c3e5-0000-4000-8000-00000000000a');
do $$
declare c jsonb; packs int; stickers int;
begin
  c := sticker_catalog();
  packs := jsonb_array_length(c->'packs');
  select count(*) into stickers from jsonb_array_elements(c->'packs') p, jsonb_array_elements(p->'stickers');
  if packs < 1 or stickers < 1 then raise exception 'FAIL catalog empty: % packs, % stickers', packs, stickers; end if;
  if (select count(*) from sticker_packs) <> packs then raise exception 'FAIL catalog/packs mismatch'; end if;
  if jsonb_typeof(c->'families') <> 'object' then raise exception 'FAIL families'; end if;
end $$;

-- ── коллекция: установка, повтор, удаление ─────────────────────────────────
do $$
declare n int;
begin
  insert into user_sticker_packs (profile_id, pack_id) values ('5717c3e5-0000-4000-8000-00000000000a', 'alexa');
  insert into user_sticker_packs (profile_id, pack_id) values ('5717c3e5-0000-4000-8000-00000000000a', 'alexa')
  on conflict do nothing;
  select count(*) into n from user_sticker_packs where pack_id = 'alexa';
  if n <> 1 then raise exception 'FAIL duplicate install: %', n; end if;
  begin
    insert into user_sticker_packs (profile_id, pack_id) values ('5717c3e5-0000-4000-8000-00000000000a', 'alexa');
    raise exception 'FAIL duplicate without on conflict accepted';
  exception when unique_violation then null;
  end;
end $$;

-- Чужая коллекция: не поставить, не увидеть, не удалить.
do $$
declare n int;
begin
  begin
    insert into user_sticker_packs (profile_id, pack_id) values ('5717c3e5-0000-4000-8000-00000000000b', 'alexa');
    raise exception 'FAIL installed into foreign collection';
  exception when insufficient_privilege then null;
  end;
  select count(*) into n from user_sticker_packs where profile_id <> '5717c3e5-0000-4000-8000-00000000000a';
  if n <> 0 then raise exception 'FAIL sees foreign collections: %', n; end if;
  delete from user_sticker_packs where profile_id = '5717c3e5-0000-4000-8000-00000000000b';
  update user_sticker_packs set position = 99 where profile_id = '5717c3e5-0000-4000-8000-00000000000b';
end $$;
reset role;
do $$
begin
  if (select count(*) from user_sticker_packs where profile_id = '5717c3e5-0000-4000-8000-00000000000b') = 0 then
    raise exception 'FAIL foreign collection deleted';
  end if;
  if exists (select 1 from user_sticker_packs where profile_id = '5717c3e5-0000-4000-8000-00000000000b' and position = 99) then
    raise exception 'FAIL foreign collection updated';
  end if;
end $$;

-- Удаление своего пака: из коллекции ушёл, из каталога — нет.
select pg_temp.as_user('5717c3e5-0000-4000-8000-00000000000a');
do $$
begin
  delete from user_sticker_packs where pack_id = 'alexa';
  if exists (select 1 from user_sticker_packs where pack_id = 'alexa') then raise exception 'FAIL uninstall'; end if;
  if not exists (select 1 from stickers where pack_id = 'alexa') then raise exception 'FAIL uninstall removed pack'; end if;
end $$;

-- ── каталог только читается ─────────────────────────────────────────────────
do $$
begin
  begin
    insert into sticker_packs (id, title, status) values ('hack', 'Хак', 'published');
    raise exception 'FAIL user created pack';
  exception when insufficient_privilege then null;
  end;
  begin
    update stickers set title = 'взлом' where id = 'basic.smile';
    raise exception 'FAIL user edited sticker';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects (bucket_id, name) values ('stickers', 'basic/smile.webp');
    raise exception 'FAIL user uploaded into stickers bucket';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ── архив и черновик ────────────────────────────────────────────────────────
reset role;
update sticker_packs set status = 'archived' where id = 'city';
insert into sticker_packs (id, title, status) values ('zz_draft', 'Черновик', 'draft');
insert into stickers (id, pack_id, key, position, image_path, title, emoji)
values ('zz_draft.one', 'zz_draft', 'one', 0, 'zz_draft/one.webp', 'один', '🙂');

select pg_temp.as_user('5717c3e5-0000-4000-8000-00000000000a');
do $$
declare c jsonb;
begin
  -- Архивный пак не поставить, но его стикеры видны (старые сообщения).
  begin
    insert into user_sticker_packs (profile_id, pack_id) values ('5717c3e5-0000-4000-8000-00000000000a', 'city');
    raise exception 'FAIL installed archived pack';
  exception when insufficient_privilege then null;
  end;
  if not exists (select 1 from stickers where pack_id = 'city') then raise exception 'FAIL archived stickers hidden'; end if;
  c := sticker_catalog();
  if not exists (select 1 from jsonb_array_elements(c->'packs') p where p->>'id' = 'city' and p->>'status' = 'archived') then
    raise exception 'FAIL archived pack missing from catalog';
  end if;
  -- Черновик не виден вовсе и не ставится.
  if exists (select 1 from sticker_packs where id = 'zz_draft') or exists (select 1 from stickers where pack_id = 'zz_draft') then
    raise exception 'FAIL draft visible';
  end if;
  begin
    insert into user_sticker_packs (profile_id, pack_id) values ('5717c3e5-0000-4000-8000-00000000000a', 'zz_draft');
    raise exception 'FAIL installed draft';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ── стикеры не удаляются даже сервером ──────────────────────────────────────
reset role;
do $$
begin
  begin
    delete from stickers where id = 'zz_draft.one';
    raise exception 'FAIL sticker deleted';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    delete from sticker_packs where id = 'basic';
    raise exception 'FAIL pack with stickers deleted';
  exception when foreign_key_violation then null;
  end;
end $$;

-- anon каталог не читает.
do $$
begin
  execute 'set local role anon';
  begin
    perform sticker_catalog();
    raise exception 'FAIL anon reads catalog';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
end $$;

\echo ALL OK
rollback;
