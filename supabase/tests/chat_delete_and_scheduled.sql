-- Проверки миграций 0033 (удаление сообщений) и 0034 (meta, silent,
-- присутствие, отложенные). Запускать на пустой базе с применёнными
-- миграциями (см. README.md): psql -v ON_ERROR_STOP=1 -f этот_файл.
-- Всё идёт в одной транзакции и откатывается, база остаётся чистой.
-- Успех — тишина и строка «ALL OK» в конце; провал — исключение с названием.

begin;

-- ── данные ──────────────────────────────────────────────────────────────────
-- A, B, C; личный диалог A–B; группа G: A — владелец, B и C — участники.

insert into profiles (id, display_name) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'A'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'B'),
  ('cccccccc-0000-0000-0000-000000000003', 'C');

insert into chat_conversations (id, direct_key, title) values
  ('d1000000-0000-0000-0000-000000000001', 'A:B', null),
  ('91000000-0000-0000-0000-000000000001', null, 'Группа');

insert into chat_members (conversation_id, profile_id, role) values
  ('d1000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'member'),
  ('d1000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'member'),
  ('91000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'owner'),
  ('91000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'member'),
  ('91000000-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000003', 'member');

create function pg_temp.as_user(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.as_admin() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

-- Личное сообщение (шифротекст) и групповое (открытый текст).
create function pg_temp.direct_msg(m uuid, sender uuid) returns void language sql as $$
  insert into chat_messages (id, conversation_id, sender_id, ciphertext, nonce, mac, signature)
  values (m, 'd1000000-0000-0000-0000-000000000001', sender, 'ct', 'n', 'm', 's');
$$;
create function pg_temp.group_msg(m uuid, sender uuid, meta jsonb default null) returns void language sql as $$
  insert into chat_messages (id, conversation_id, sender_id, body, meta)
  values (m, '91000000-0000-0000-0000-000000000001', sender, 'текст', meta);
$$;

\echo == 0033: удаление
select pg_temp.direct_msg('11000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
select pg_temp.direct_msg('11000000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000002');
select pg_temp.group_msg('22000000-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000003');
select pg_temp.group_msg('22000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001');

-- A удаляет своё личное → надгробие без содержимого.
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
do $$
declare n int;
begin
  select count(*) into n from delete_chat_messages(array['11000000-0000-0000-0000-000000000001'::uuid]);
  assert n = 1, 'автор удаляет своё личное';
  -- чужое личное у всех не удалить
  select count(*) into n from delete_chat_messages(array['11000000-0000-0000-0000-000000000002'::uuid]);
  assert n = 0, 'чужое в личном удалить нельзя';
end $$;

-- B видит надгробие, содержимого нет.
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000002');
do $$
declare r chat_messages;
begin
  select * into r from chat_messages where id = '11000000-0000-0000-0000-000000000001';
  assert r.deleted_at is not null, 'надгробие видно собеседнику';
  assert r.ciphertext is null and r.nonce is null and r.mac is null and r.signature is null,
    'шифротекст стёрт';
end $$;

-- Прямого delete и update нет вообще.
do $$
begin
  begin
    delete from chat_messages where id = '11000000-0000-0000-0000-000000000002';
    assert false, 'прямой delete должен быть запрещён';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Группа: участник (B) чужое не удаляет, владелец (A) — удаляет чужое.
do $$
declare n int;
begin
  select count(*) into n from delete_chat_messages(array['22000000-0000-0000-0000-000000000001'::uuid]);
  assert n = 0, 'участник чужое в группе не удаляет';
end $$;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
do $$
declare n int;
begin
  select count(*) into n from delete_chat_messages(array['22000000-0000-0000-0000-000000000001'::uuid]);
  assert n = 1, 'владелец группы удаляет чужое';
  -- повторное удаление ничего не возвращает
  select count(*) into n from delete_chat_messages(array['22000000-0000-0000-0000-000000000001'::uuid]);
  assert n = 0, 'удалённое второй раз не удаляется';
end $$;

-- Список чатов: удалённое не «последнее» и не «непрочитанное».
do $$
declare last uuid; unread int;
begin
  select last_id, unread_count into last, unread from my_chats('d1000000-0000-0000-0000-000000000001');
  assert last = '11000000-0000-0000-0000-000000000002', 'последнее — не удалённое';
  select last_id, unread_count into last, unread from my_chats('91000000-0000-0000-0000-000000000001');
  assert last = '22000000-0000-0000-0000-000000000002', 'в группе последнее — не удалённое';
  assert unread = 0, 'удалённое не считается непрочитанным';
end $$;

\echo == 0034: meta и silent
select pg_temp.as_admin();
do $$
declare r chat_messages;
begin
  perform pg_temp.group_msg('33000000-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001', '{"r":{"id":"x","n":"A","t":"привет"}}');
  select * into r from chat_messages where id = '33000000-0000-0000-0000-000000000001';
  assert r.meta->'r'->>'n' = 'A', 'meta хранится у группового';
  assert r.silent = false, 'silent по умолчанию выключен';

  begin
    insert into chat_messages (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, meta)
    values ('33000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'ct', 'n', 'm', 's', '{"r":{}}');
    assert false, 'meta у шифрованного должна быть запрещена';
  exception when check_violation then null;
  end;

  -- удаление стирает meta
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', true);
  perform delete_chat_messages(array['33000000-0000-0000-0000-000000000001'::uuid]);
  select * into r from chat_messages where id = '33000000-0000-0000-0000-000000000001';
  assert r.meta is null and r.body is null, 'надгробие без meta и текста';
end $$;

\echo == 0034: присутствие
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
do $$
begin
  begin
    perform 1 from user_presence;
    assert false, 'таблица присутствия не читается клиентом';
  exception when insufficient_privilege then null;
  end;
  perform touch_last_seen();
  perform touch_last_seen();  -- повторный вызов обновляет, а не падает
end $$;
select pg_temp.as_admin();
do $$
begin
  assert (select count(*) from user_presence) = 1, 'одна строка на человека';
  assert chat_peer_online('d1000000-0000-0000-0000-000000000001',
                          'bbbbbbbb-0000-0000-0000-000000000002'),
    'A в сети — для B это «собеседник в сети»';
  assert not chat_peer_online('d1000000-0000-0000-0000-000000000001',
                              'aaaaaaaa-0000-0000-0000-000000000001'),
    'B не в сети';
  update user_presence set seen_at = now() - interval '5 minutes';
  assert not chat_peer_online('d1000000-0000-0000-0000-000000000001',
                              'bbbbbbbb-0000-0000-0000-000000000002'),
    'пять минут назад — уже не в сети';
end $$;

\echo == 0034: отложенные — правила вставки
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
do $$
begin
  insert into chat_scheduled_messages
    (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, send_at)
  values ('44000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-000000000001', 'ct', 'n', 'm', 's', now() + interval '1 hour');

  begin  -- и время, и «в сети» одновременно
    insert into chat_scheduled_messages
      (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, send_at, when_online)
    values ('44000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'ct', 'n', 'm', 's', now() + interval '1 hour', true);
    assert false, 'нужен ровно один способ';
  exception when check_violation then null;
  end;

  begin  -- ни того ни другого
    insert into chat_scheduled_messages
      (id, conversation_id, sender_id, ciphertext, nonce, mac, signature)
    values ('44000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'ct', 'n', 'm', 's');
    assert false, 'нужен хотя бы один способ';
  exception when check_violation then null;
  end;

  begin  -- открытый текст в личный диалог
    insert into chat_scheduled_messages
      (id, conversation_id, sender_id, body, send_at)
    values ('44000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'открытый', now() + interval '1 hour');
    assert false, 'в личный диалог — только шифротекст';
  exception when insufficient_privilege then null;
  end;

  begin  -- от чужого имени
    insert into chat_scheduled_messages
      (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, send_at)
    values ('44000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000002', 'ct', 'n', 'm', 's', now() + interval '1 hour');
    assert false, 'от чужого имени нельзя';
  exception when insufficient_privilege then null;
  end;

  begin  -- дальше года
    insert into chat_scheduled_messages
      (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, send_at)
    values ('44000000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'ct', 'n', 'm', 's', now() + interval '400 days');
    assert false, 'дальше года нельзя';
  exception when sqlstate '22023' then null;
  end;
end $$;

-- B своё видит, чужое — нет.
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000002');
do $$
begin
  assert (select count(*) from chat_scheduled_messages) = 0, 'чужие отложенные не видны';
  delete from chat_scheduled_messages;  -- и не удаляются
end $$;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
do $$
begin
  assert (select count(*) from chat_scheduled_messages) = 1, 'свои отложенные видны, чужое удаление их не тронуло';
end $$;

\echo == 0034: выпуск отложенных
select pg_temp.as_admin();
do $$
declare n int;
begin
  -- время ещё не пришло
  assert release_scheduled_chat_messages() = 0, 'раньше срока не уходит';
  assert exists (select 1 from chat_scheduled_messages where id = '44000000-0000-0000-0000-000000000001');

  update chat_scheduled_messages set send_at = now() - interval '1 minute'
   where id = '44000000-0000-0000-0000-000000000001';
  assert release_scheduled_chat_messages() = 1, 'по времени уходит';
  assert exists (select 1 from chat_messages
                  where id = '44000000-0000-0000-0000-000000000001' and ciphertext = 'ct'),
    'то же сообщение, тот же id и шифротекст';
  assert not exists (select 1 from chat_scheduled_messages
                      where id = '44000000-0000-0000-0000-000000000001'), 'из очереди убрано';
end $$;

-- «Когда будет в сети»: пока A не в сети (пять минут назад), B ничего не получит…
do $$
begin
  insert into chat_scheduled_messages
    (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, when_online, silent)
  values ('55000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-000000000002', 'ct', 'n', 'm', 's', true, true);
  assert release_scheduled_chat_messages() = 0, 'собеседник не в сети — ждём';
  update user_presence set seen_at = now();   -- A появился в сети
  assert release_scheduled_chat_messages() = 1, 'собеседник появился — уходит';
  assert (select silent from chat_messages where id = '55000000-0000-0000-0000-000000000001'),
    'флаг «без звука» дошёл до сообщения';
end $$;

-- Заблокированному или в закрытом чате — тихо удаляется, не отправляется.
do $$
begin
  insert into user_blocks (blocker_id, blocked_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002');
  insert into chat_scheduled_messages
    (id, conversation_id, sender_id, ciphertext, nonce, mac, signature, send_at)
  values ('66000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-000000000002', 'ct', 'n', 'm', 's', now() - interval '1 minute');
  assert release_scheduled_chat_messages() = 0, 'заблокированному не отправляется';
  assert not exists (select 1 from chat_scheduled_messages
                      where id = '66000000-0000-0000-0000-000000000001'), 'и из очереди убирается';
  assert not exists (select 1 from chat_messages
                      where id = '66000000-0000-0000-0000-000000000001');
  delete from user_blocks;

  update chat_conversations set closed_at = now() where id = '91000000-0000-0000-0000-000000000001';
  insert into chat_scheduled_messages (id, conversation_id, sender_id, body, send_at)
  values ('66000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001',
          'cccccccc-0000-0000-0000-000000000003', 'в закрытый', now() - interval '1 minute');
  assert release_scheduled_chat_messages() = 0, 'в закрытый чат не отправляется';
  assert not exists (select 1 from chat_scheduled_messages
                      where id = '66000000-0000-0000-0000-000000000002');
  update chat_conversations set closed_at = null where id = '91000000-0000-0000-0000-000000000001';
end $$;

-- Групповое с цитатой уходит с meta; вышедшего из группы не отправляем.
do $$
begin
  insert into chat_scheduled_messages (id, conversation_id, sender_id, body, meta, send_at)
  values ('77000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001',
          'cccccccc-0000-0000-0000-000000000003', 'ответ', '{"r":{"id":"q","n":"A","t":"?"}}',
          now() - interval '1 minute');
  assert release_scheduled_chat_messages() = 1, 'групповое уходит';
  assert (select meta->'r'->>'t' from chat_messages where id = '77000000-0000-0000-0000-000000000001') = '?',
    'цитата доехала';

  insert into chat_scheduled_messages (id, conversation_id, sender_id, body, send_at)
  values ('77000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001',
          'cccccccc-0000-0000-0000-000000000003', 'я уже не в группе', now() - interval '1 minute');
  delete from chat_members where conversation_id = '91000000-0000-0000-0000-000000000001'
                             and profile_id = 'cccccccc-0000-0000-0000-000000000003';
  assert release_scheduled_chat_messages() = 0, 'вышедший из группы не пишет';
end $$;

-- Антиспам: упавшее на лимите остаётся в очереди, а не пропадает.
do $$
declare i int; have int;
begin
  -- Добиваем до лимита (60 в минуту): часть сообщений A уже есть выше.
  select count(*) into have from chat_messages
   where sender_id = 'aaaaaaaa-0000-0000-0000-000000000001' and sent_at > now() - interval '1 minute';
  for i in 1..(60 - have) loop
    insert into chat_messages (id, conversation_id, sender_id, body)
    values (gen_random_uuid(), '91000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'спам ' || i);
  end loop;
  insert into chat_scheduled_messages (id, conversation_id, sender_id, body, send_at)
  values ('88000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-000000000001', 'после лимита', now() - interval '1 minute');
  assert release_scheduled_chat_messages() = 0, 'лимит сообщений в минуту соблюдается';
  assert exists (select 1 from chat_scheduled_messages where id = '88000000-0000-0000-0000-000000000001'),
    'не отправленное из-за лимита остаётся в очереди';
end $$;

-- Не больше 50 отложенных на человека.
do $$
declare i int;
begin
  delete from chat_scheduled_messages;
  for i in 1..50 loop
    insert into chat_scheduled_messages (id, conversation_id, sender_id, body, send_at)
    values (gen_random_uuid(), '91000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'x', now() + interval '1 day');
  end loop;
  begin
    insert into chat_scheduled_messages (id, conversation_id, sender_id, body, send_at)
    values (gen_random_uuid(), '91000000-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', 'x', now() + interval '1 day');
    assert false, '51-е отложенное должно быть отклонено';
  exception when sqlstate 'P0001' then null;
  end;
end $$;

\echo ALL OK
rollback;
