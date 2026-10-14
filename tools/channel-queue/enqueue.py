"""Кладёт пост в очередь канала (миграция 0089).

    SUPABASE_URL=… SUPABASE_SERVICE_KEY=… python -I enqueue.py \
        --handle chawo --ref dev-news-2026-10-15 --at "2026-10-15 20:00" \
        --body текст.md [--image картинка.png]

--at — московское время. Картинка заливается в публичный бакет post-media
(папка queue/) и вставляется в начало текста Markdown-ссылкой, как в прежних
постах канала. Повтор с тем же --ref ничего не дублирует (ref уникален).
Ключ проще всего передать через enqueue.ps1.
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
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--handle', required=True)
    p.add_argument('--ref', required=True)
    p.add_argument('--at', required=True)
    p.add_argument('--body', required=True, help='файл с текстом (Markdown)')
    p.add_argument('--image')
    a = p.parse_args()

    when = datetime.datetime.strptime(a.at, '%Y-%m-%d %H:%M').replace(tzinfo=MSK)
    body = open(a.body, encoding='utf-8-sig').read().strip()
    if a.image:
        name = f'queue/{a.ref}{os.path.splitext(a.image)[1].lower()}'
        mime = 'image/png' if name.endswith('.png') else 'image/jpeg'
        status, resp = call('POST', f'/storage/v1/object/post-media/{name}', open(a.image, 'rb').read(),
                            {'Content-Type': mime, 'x-upsert': 'true'})
        if status not in (200, 201):
            sys.exit(f'картинка не загрузилась: {status} {resp[:200]!r}')
        body = f'![ChaWo]({URL}/storage/v1/object/public/post-media/{name})\n\n{body}'

    row = {'handle': a.handle, 'source_ref': a.ref, 'body': body, 'publish_at': when.isoformat()}
    status, resp = call('POST', '/rest/v1/channel_post_queue', json.dumps(row).encode(),
                        {'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates'})
    if status not in (200, 201, 204):
        sys.exit(f'очередь не приняла: {status} {resp[:300]!r}')
    print(f'в очереди: {a.ref} на {when:%d.%m %H:%M} МСК')


main()
