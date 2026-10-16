"""Видео-пост виртуального автора: скачать ролик, залить в Storage, поставить в очередь.

    SUPABASE_URL=… SUPABASE_SERVICE_KEY=… python -I post_video.py пачка.json
    (ключ проще передать через post_video.ps1)

пачка.json — список постов:
  [{"author": "клипов", "ref": "klipov-2026-10-16-a1", "at": "2026-10-16 21:00",
    "url": "https://youtu.be/VIDEO_ID", "title": "Заголовок без ссылок",
    "tags": "#Сочи #shorts",
    "credit_name": "Имя/канал автора оригинала",
    "credit_url": "https://www.youtube.com/@channel"}]

Автор ролика указывается всегда — строка «Видео:» в посте обязательна, как
«Фото:» у фотопостов. Ссылка на оригинал тоже обязательна («Оригинал:»), чтобы
зрители могли прийти на канал автора. Это не снимает риск авторских прав
(решение Алексея 16.10 — репостим сам файл, не только анонс), но держит тот
же минимум уважения к источнику, что у остальных авторов.

kind в самой базе почти не важен: клиент определяет фото/видео по расширению
файла в media_urls (lib/core/media/media_kind.dart), не по колонке post_kind —
поэтому отдельный "video"-режим очереди не нужен, тот же author_post_queue.
"""
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
MSK = datetime.timezone(datetime.timedelta(hours=3))
MAX_BYTES = 80 * 1024 * 1024  # запас под лимит бакета 250 МБ — Shorts короткие, не должно даже близко подходить

# Отдельный пустой YouTube-аккаунт (не основной Алексея), куки экспортированы
# расширением «Get cookies.txt LOCALLY». Без них и без --remote-components
# ejs:github YouTube отвечает либо «Sign in to confirm you're not a bot»,
# либо «The page needs to be reloaded» (JS-защита подписи). Куки обновлять,
# когда истекут — тогда снова вернётся ошибка бота.
YT_COOKIES = os.environ.get('YT_COOKIES', r'D:\temp\bloggers\youtube_cookies.txt')

HERE = os.path.dirname(os.path.abspath(__file__))
AUTHORS = {}
for fname in ('authors_video.json', 'authors_extra.json'):
    fpath = os.path.join(HERE, fname)
    if os.path.exists(fpath):
        for k, v in json.load(open(fpath, encoding='utf-8')).items():
            AUTHORS.setdefault(k, (v['nick'], v['name']))


def call(method, path, data=None, headers=None):
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header('apikey', KEY)
    req.add_header('Authorization', 'Bearer ' + KEY)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:300]


def check(item):
    problems = []
    if not item.get('credit_name'):
        problems.append('нет credit_name (автор оригинала)')
    if not item.get('credit_url'):
        problems.append('нет credit_url (ссылка на канал)')
    if not item.get('url'):
        problems.append('нет url ролика')
    if len(re.findall(r'#\w{2,}', item.get('tags', ''))) < 2:
        problems.append('нужно 2–3 хэштега')
    return problems


def download(url, dest_dir):
    out = os.path.join(dest_dir, 'video.mp4')
    cmd = ['yt-dlp', '--remote-components', 'ejs:github']
    if os.path.exists(YT_COOKIES):
        cmd += ['--cookies', YT_COOKIES]
    cmd += ['-S', 'res:1080,ext:mp4:m4a', '--merge-output-format', 'mp4', '-o', out, url]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
    if proc.returncode != 0 or not os.path.exists(out):
        raise RuntimeError(f'yt-dlp не скачал {url}: {proc.stderr[-500:]}')
    size = os.path.getsize(out)
    if size > MAX_BYTES:
        raise RuntimeError(f'{url}: файл {size // 1024 // 1024} МБ, больше лимита {MAX_BYTES // 1024 // 1024} МБ')
    return out


def main(path):
    items = json.load(open(path, encoding='utf-8'))
    bad = 0
    for it in items:
        nick, name = AUTHORS[it['author']]
        problems = check(it)
        if problems:
            print(it['ref'], 'пропущен:', '; '.join(problems))
            bad += 1
            continue
        body = (f"{it['title'].replace('*', '')}\n\n{it['tags']}\n\n"
                f"Видео: [{it['credit_name']}]({it['credit_url']})\n"
                f"Оригинал: [смотреть на YouTube]({it['url']})")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                local = download(it['url'], tmp)
                remote = f"authors/{it['ref']}.mp4"
                with open(local, 'rb') as f:
                    status, resp = call('POST', f'/storage/v1/object/post-media/{remote}', f.read(),
                                        {'Content-Type': 'video/mp4', 'x-upsert': 'true'})
        except RuntimeError as e:
            print(it['ref'], 'ошибка скачивания:', e)
            bad += 1
            continue
        if status not in (200, 201):
            print(it['ref'], 'видео не загрузилось', status, resp)
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
