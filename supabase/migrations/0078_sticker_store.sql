-- Магазин стикеров: общий каталог паков, коллекция каждого пользователя.
--
-- Стикер в сообщении — это его id (`<пак>.<ключ>`) в служебной части
-- сообщения (0032/0034): в группах в колонке meta, в личных чатах — внутри
-- шифротекста. Поэтому внешнего ключа «сообщение → стикер» нет и быть не
-- может, а значит стикеры физически не удаляются никогда: пак снимают с
-- публикации (status = 'archived'), и уже отправленные сообщения продолжают
-- его показывать.
--
-- Каталог наполняет сервер (service_role) скриптом tools/stickers/
-- publish_packs.py. Колонки owner_id и статус 'review' — задел под паки от
-- пользователей: публиковать их сейчас нельзя (нет ни политик записи, ни
-- функций), появятся вместе с модерацией.

create table sticker_packs (
  id          text primary key check (id ~ '^[a-z0-9_]{1,32}$'),
  title       text not null check (length(title) between 1 and 60),
  description text check (length(description) <= 500),
  publisher   text not null default 'Команда ChaWo' check (length(publisher) between 1 and 60),
  owner_id    uuid references profiles on delete set null,
  category    text check (length(category) <= 32),
  cover_path  text,
  version     integer not null default 1 check (version >= 1),
  status      text not null default 'draft'
              check (status in ('draft', 'review', 'published', 'archived')),
  -- Ставится новым пользователям при регистрации.
  is_default  boolean not null default false,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table stickers (
  id         text primary key check (id ~ '^[a-z0-9_]{1,32}\.[a-z0-9_]{1,48}$'),
  pack_id    text not null references sticker_packs on delete restrict,
  key        text not null,
  position   integer not null check (position >= 0),
  image_path text not null,
  thumb_path text,
  width      integer not null default 512,
  height     integer not null default 512,
  -- Название (оно же альтернативный текст) и слова для поиска.
  title      text not null check (length(title) between 1 and 60),
  emoji      text not null check (length(emoji) between 1 and 16),
  synonyms   text[] not null default '{}',
  emotions   text[] not null default '{}',
  created_at timestamptz not null default now(),
  check (id = pack_id || '.' || key)
);

create index stickers_pack_position on stickers (pack_id, position);

-- Семейства эмоций для поиска: «любовь» находит все стикеры семейства love.
create table sticker_families (
  key   text primary key check (key ~ '^[a-z_]{1,32}$'),
  words text[] not null default '{}'
);

create table user_sticker_packs (
  profile_id   uuid not null references profiles on delete cascade,
  pack_id      text not null references sticker_packs on delete cascade,
  installed_at timestamptz not null default now(),
  -- Порядок вкладок в панели; null — по времени установки.
  position     integer,
  primary key (profile_id, pack_id)
);

-- Отправленный стикер может понадобиться в любой момент, поэтому стикер не
-- удаляется даже сервером: только снять пак с публикации.
create function stickers_forbid_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'стикеры не удаляются: сообщения ссылаются на них по id. Снимите пак с публикации (status = archived)';
end;
$$;

create trigger stickers_no_delete before delete on stickers
  for each row execute function stickers_forbid_delete();

create function sticker_packs_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger sticker_packs_touch before update on sticker_packs
  for each row execute function sticker_packs_touch();

-- ── права ───────────────────────────────────────────────────────────────────

alter table sticker_packs enable row level security;
alter table stickers enable row level security;
alter table sticker_families enable row level security;
alter table user_sticker_packs enable row level security;

revoke all on sticker_packs, stickers, sticker_families, user_sticker_packs from anon, authenticated;
grant select on sticker_packs, stickers, sticker_families to authenticated;
grant select, insert, delete on user_sticker_packs to authenticated;
grant update (position) on user_sticker_packs to authenticated;

-- Снятый с публикации пак виден: по нему открывается стикер из старого
-- сообщения. Черновики и паки на модерации не видны никому, кроме сервера.
create policy "паки: опубликованные и архивные" on sticker_packs
  for select to authenticated
  using (status in ('published', 'archived'));

create policy "стикеры: из видимых паков" on stickers
  for select to authenticated
  using (exists (
    select 1 from sticker_packs p
    where p.id = stickers.pack_id and p.status in ('published', 'archived')
  ));

create policy "семейства: всем" on sticker_families
  for select to authenticated using (true);

create policy "коллекция: вижу свою" on user_sticker_packs
  for select to authenticated using (profile_id = auth.uid());

-- Установить можно только опубликованный пак и только себе.
create policy "коллекция: ставлю себе" on user_sticker_packs
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and exists (select 1 from sticker_packs p where p.id = pack_id and p.status = 'published')
  );

create policy "коллекция: убираю своё" on user_sticker_packs
  for delete to authenticated using (profile_id = auth.uid());

create policy "коллекция: порядок своих" on user_sticker_packs
  for update to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- ── каталог одним запросом ──────────────────────────────────────────────────

-- Всё, что нужно приложению: семейства, видимые паки и их стикеры по
-- порядку. Картинки — пути в публичном бакете stickers.
create function sticker_catalog() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'families', coalesce((select jsonb_object_agg(f.key, to_jsonb(f.words)) from sticker_families f), '{}'::jsonb),
    'packs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'description', p.description,
        'publisher', p.publisher,
        'category', p.category,
        'cover', p.cover_path,
        'version', p.version,
        'status', p.status,
        'stickers', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', s.id,
            'emoji', s.emoji,
            'title', s.title,
            'synonyms', to_jsonb(s.synonyms),
            'emotions', to_jsonb(s.emotions),
            'image', s.image_path,
            'thumb', s.thumb_path,
            'w', s.width,
            'h', s.height
          ) order by s.position)
          from stickers s where s.pack_id = p.id
        ), '[]'::jsonb)
      ) order by p.sort_order, p.created_at)
      from sticker_packs p
    ), '[]'::jsonb)
  );
$$;

revoke all on function sticker_catalog() from public, anon;
grant execute on function sticker_catalog() to authenticated;

-- ── новые пользователи ──────────────────────────────────────────────────────

create function sticker_default_packs() returns trigger
language plpgsql security definer set search_path = public set row_security = off as $$
begin
  insert into user_sticker_packs (profile_id, pack_id)
  select new.id, p.id from sticker_packs p
  where p.is_default and p.status = 'published'
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function sticker_default_packs() from public;

create trigger profiles_sticker_default_packs
  after insert on profiles
  for each row execute function sticker_default_packs();

-- ── файлы ───────────────────────────────────────────────────────────────────

-- Публичное чтение (как у post-media): стикер из сообщения должен
-- открываться у любого получателя без подписанных ссылок. Писать может
-- только сервер: политик на запись для authenticated нет.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('stickers', 'stickers', true, 1048576, array['image/webp', 'image/png'])
on conflict (id) do update set public = true;
