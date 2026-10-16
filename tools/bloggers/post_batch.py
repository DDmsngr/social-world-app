"""Пачка постов виртуальных авторов: карточка + очередь за один запуск.

    SUPABASE_URL=… SUPABASE_SERVICE_KEY=… python -I post_batch.py пачка.json
    (ключ проще передать через post_batch.ps1)

пачка.json — список постов:
  {"author": "sonya", "ref": "sonya-2026-10-15-b1", "at": "2026-10-15 13:00",
   "title": "Заголовок с *акцентом*", "body": "Текст без ссылок и хэштегов",
   "tags": "#Сочи #парки #прогулки",
   "photo": "D:/temp/bloggers/b1/01.jpg", "meta": "D:/temp/bloggers/b1/01.json"}

Сборка поста: текст + хэштеги + «Источник: [Википедия](адрес статьи)» и
«Фото: автор, лицензия, [Wikimedia Commons](страница файла)» из meta.json
(его пишет wiki_pack.py). Если источник другой, вместо meta — поля
"source_name", "source_url", "photo_credit", "photo_page".
Точка на карте: координаты статьи из meta.json сами (wiki_pack.py), либо
"place": {"title", "lat", "lon"}, либо "place": false, если пост не о месте.
Ничего не выдумывается: текст пишет человек по прочитанному источнику.
"""
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import card  # noqa: E402

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
MSK = datetime.timezone(datetime.timedelta(hours=3))
OUT = os.environ.get('CARDS_DIR', r'D:\temp\bloggers\cards')

# ключ → (ник, имя на карточке)
AUTHORS = {
    'sonya': ('sonya_gid', 'Соня Прибрежная'),
    'mark': ('mark_afisha', 'Марк Афишин'),
    'ilya': ('ilya_facts', 'Илья Горский'),
    'tikhon': ('tikhon_zveri', 'Тихон Зверев'),
    'vera': ('vera_kuhnya', 'Вера Кухарина'),
    'artem': ('artem_volna', 'Артём Волнов'),
}
if os.path.exists(os.path.join(os.path.dirname(__file__), 'authors_extra.json')):
    for k, v in json.load(open(os.path.join(os.path.dirname(__file__), 'authors_extra.json'), encoding='utf-8')).items():
        AUTHORS[k] = (v['nick'], v['name'])
        card.BRAND[k] = (tuple(v['accent']), tuple(v['bg']))


def call(method, path, data=None, headers=None):
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header('apikey', KEY)
    req.add_header('Authorization', 'Bearer ' + KEY)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:300]


def check(item, body):
    problems = []
    if not 250 <= len(body) <= 2600:
        problems.append(f'длина текста {len(body)}')
    if len(re.findall(r'#\w{2,}', item.get('tags', ''))) < 2:
        problems.append('нужно 2–3 хэштега')
    if re.search(r'(?<!\]\()https?://', item['body']):
        problems.append('в тексте голые ссылки (они добавляются сами)')
    return problems


def place_of(it, meta):
    """Точка на карте для поста о месте (0098): из пачки ("place": {"title",
    "lat", "lon"}) или из координат статьи Википедии в meta.json. "place": false —
    пост не о месте (статья про море или явление тоже бывает с координатами)."""
    p = it.get('place')
    if p is False:
        return None
    if isinstance(p, dict):
        return p['title'], float(p['lat']), float(p['lon'])
    if meta.get('lat') is not None and meta.get('lon') is not None:
        return meta['title'], float(meta['lat']), float(meta['lon'])
    return None


def main(path):
    items = json.load(open(path, encoding='utf-8'))
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for it in items:
        nick, name = AUTHORS[it['author']]
        meta = json.load(open(it['meta'], encoding='utf-8')) if it.get('meta') else {}
        src_name = it.get('source_name') or 'Википедия'
        src_url = it.get('source_url') or meta.get('url')
        credit = it.get('photo_credit') or f"{meta.get('artist', 'автор не указан')}, {meta.get('license', '')}".strip(', ')
        photo_page = it.get('photo_page') or meta.get('commons')
        # Скобки в адресе (…/Парк_(Сочи)) обрывали бы ссылку [подпись](адрес).
        src_url, photo_page = (u and u.replace('(', '%28').replace(')', '%29') for u in (src_url, photo_page))
        body = (f"{it['title'].replace('*', '')}\n\n{it['body'].strip()}\n\n{it['tags']}\n\n"
                f"Источник: [{src_name}]({src_url})\nФото: {credit}, [Wikimedia Commons]({photo_page})")
        problems = check(it, it['body'])
        if problems:
            print(it['ref'], 'пропущен:', '; '.join(problems))
            bad += 1
            continue
        image = os.path.join(OUT, it['ref'] + '.png')
        card.render(it['photo'], it['title'], name, f'Фото: {credit}'[:70], card.BRAND[it['author']], image)
        ext = '.png'
        remote = f"authors/{it['ref']}{ext}"
        with open(image, 'rb') as f:
            status, resp = call('POST', f'/storage/v1/object/post-media/{remote}', f.read(),
                                {'Content-Type': 'image/png', 'x-upsert': 'true'})
        if status not in (200, 201):
            print(it['ref'], 'картинка не загрузилась', status, resp)
            bad += 1
            continue
        status, rows = call('GET', f'/rest/v1/profiles?username=eq.{nick}&select=id')
        if status != 200 or not rows:
            print(it['ref'], 'нет автора', nick)
            bad += 1
            continue
        when = datetime.datetime.strptime(it['at'], '%Y-%m-%d %H:%M').replace(tzinfo=MSK)
        row = {'author_id': rows[0]['id'], 'source_ref': it['ref'], 'body': body,
               'media_urls': [f'{URL}/storage/v1/object/public/post-media/{remote}'],
               'publish_at': when.isoformat()}
        place = place_of(it, meta)
        if place:
            row.update(place_title=place[0], place_lat=place[1], place_lon=place[2])
        status, resp = call('POST', '/rest/v1/author_post_queue?on_conflict=source_ref', json.dumps(row).encode(),
                            {'Content-Type': 'application/json',
                             'Prefer': 'resolution=merge-duplicates,return=minimal'})
        if status not in (200, 201, 204):
            print(it['ref'], 'очередь не приняла', status, resp)
            bad += 1
            continue
        print('в очереди', it['ref'], it['at'])
    print('готово, ошибок:', bad)


main(sys.argv[1])
