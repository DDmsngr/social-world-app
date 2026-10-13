-- Тем, кто уже пользуется ChaWo, — те четыре пака, что были у них в
-- приложении до магазина (тогда стикеры были вшиты в сборку). Без этого
-- панель стикеров у них после обновления оказалась бы пустой.
-- Накатывается после публикации паков (tools/stickers/publish.ps1); на
-- пустой базе ничего не делает.

insert into user_sticker_packs (profile_id, pack_id, installed_at, position)
select pr.id, p.id, now(), p.sort_order
from profiles pr
cross join sticker_packs p
where p.id in ('basic', 'more', 'city', 'chao') and p.status = 'published'
on conflict do nothing;
