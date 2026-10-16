"""Точка на карте для уже вышедших постов авторов (миграция 0098).

    powershell -File tools\bloggers\attach_places.ps1            # что будет привязано
    powershell -File tools\bloggers\attach_places.ps1 --apply ref1 ref2 …   # привязать эти

Берёт пост из очереди авторов (вышедший или ещё ждущий), в тексте ищет «Источник: [Википедия](адрес)»,
у статьи спрашивает координаты. Нет координат — поста в списке нет. Какие
привязывать, решает человек: статья про море или явление тоже бывает с точкой.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
UA = {'User-Agent': 'ChaWo-editor/1.0 (https://deepdrift.tech)'}


def call(method, path, data=None):
    req = urllib.request.Request(URL + path, method=method,
                                 data=None if data is None else json.dumps(data).encode())
    req.add_header('apikey', KEY)
    req.add_header('Authorization', 'Bearer ' + KEY)
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {path}: {e.code} {e.read().decode("utf-8", "replace")[:300]}')


def coords(article_url):
    title = urllib.parse.unquote(article_url.split('/wiki/', 1)[1]).replace('_', ' ')
    q = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'prop': 'coordinates',
                                'titles': title, 'redirects': 1})
    req = urllib.request.Request('https://ru.wikipedia.org/w/api.php?' + q, headers=UA)
    page = next(iter(json.load(urllib.request.urlopen(req, timeout=40))['query']['pages'].values()))
    c = next(iter(page.get('coordinates') or []), None)
    if not c or c.get('globe', 'earth') != 'earth':
        return None
    return page['title'], c['lat'], c['lon']


def candidates():
    rows = call('GET', '/rest/v1/author_post_queue?status=in.(published,queued)&place_title=is.null'
                       '&select=source_ref,post_id,status,body&order=publish_at')
    for row in rows:
        m = re.search(r'Источник: \[Википедия\]\((https://ru\.wikipedia\.org/wiki/[^)\s]+)\)', row['body'])
        if not m:
            continue
        found = coords(m.group(1))
        if found:
            yield row, found


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    if len(sys.argv) > 1 and sys.argv[1] == '--apply':
        wanted = set(sys.argv[2:])
        for row, (title, lat, lon) in candidates():
            if row['source_ref'] not in wanted:
                continue
            if row['status'] == 'queued':
                # Ещё не вышел: место заведёт сама очередь при выпуске.
                call('PATCH', '/rest/v1/author_post_queue?source_ref=eq.' + urllib.parse.quote(row['source_ref']),
                     {'place_title': title, 'place_lat': lat, 'place_lon': lon})
            else:
                call('POST', '/rest/v1/rpc/attach_author_post_place',
                     {'in_post': row['post_id'], 'in_title': title, 'in_lat': lat, 'in_lon': lon})
            print('привязано', row['source_ref'], title)
    else:
        for row, (title, lat, lon) in candidates():
            print(f"{row['status']:9} {row['source_ref']:28} {title}  {lat:.4f},{lon:.4f}")
