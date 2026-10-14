"""Кладёт пост виртуального автора в очередь (миграция 0091).

    SUPABASE_URL=… SUPABASE_SERVICE_KEY=… python -I enqueue_post.py \
        --author sonya_gid --ref sonya-2026-10-15 --at "2026-10-15 10:00" \
        --body текст.txt [--image фото.jpg]

--at — московское время. Текст идёт как есть: в конце обязательно строка
«Источник: ссылка» и, если есть фото, «Фото: автор, лицензия, ссылка».
Картинка заливается в публичный бакет post-media (папка authors/) и уходит в
media_urls поста. Повтор с тем же --ref обновляет запись очереди, пока она
не вышла. Ключ проще передать через enqueue_post.ps1.
"""
import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
MSK = datetime.timezone(datetime.timedelta(hours=3))


def call(method, path, data=None, headers=None):
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header('apikey', KEY)
    req.add_header('Authorization', 'Bearer ' + KEY)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:300]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--author', required=True, help='ник автора')
    p.add_argument('--ref', required=True)
    p.add_argument('--at', required=True)
    p.add_argument('--body', required=True)
    p.add_argument('--image')
    a = p.parse_args()

    body = open(a.body, encoding='utf-8-sig').read().strip()
    if 'Источник:' not in body:
        sys.exit('в тексте нет строки «Источник: …» — посты без источника не выходят')
    status, rows = call('GET', f'/rest/v1/profiles?username=eq.{a.author}&select=id')
    if status != 200 or not rows:
        sys.exit(f'автор {a.author} не найден')
    author_id = rows[0]['id']
    status, rows = call('GET', f'/rest/v1/bot_authors?profile_id=eq.{author_id}&select=profile_id')
    if status != 200 or not rows:
        sys.exit(f'{a.author} не виртуальный автор: от имени людей публиковать нельзя')

    media = []
    if a.image:
        if 'Фото:' not in body:
            sys.exit('есть картинка, но в тексте нет строки «Фото: автор, лицензия, ссылка»')
        ext = os.path.splitext(a.image)[1].lower()
        name = f'authors/{a.ref}{ext}'
        mime = 'image/png' if ext == '.png' else 'image/jpeg'
        status, resp = call('POST', f'/storage/v1/object/post-media/{name}', open(a.image, 'rb').read(),
                            {'Content-Type': mime, 'x-upsert': 'true'})
        if status not in (200, 201):
            sys.exit(f'картинка не загрузилась: {status} {resp}')
        media.append(f'{URL}/storage/v1/object/public/post-media/{name}')

    when = datetime.datetime.strptime(a.at, '%Y-%m-%d %H:%M').replace(tzinfo=MSK)
    row = {'author_id': author_id, 'source_ref': a.ref, 'body': body,
           'media_urls': media, 'publish_at': when.isoformat()}
    status, resp = call('POST', '/rest/v1/author_post_queue?on_conflict=source_ref', json.dumps(row).encode(),
                        {'Content-Type': 'application/json',
                         'Prefer': 'resolution=merge-duplicates,return=minimal'})
    if status not in (200, 201, 204):
        sys.exit(f'очередь не приняла: {status} {resp}')
    print(f'в очереди: {a.ref} ({a.author}) на {when:%d.%m %H:%M} МСК')


main()
