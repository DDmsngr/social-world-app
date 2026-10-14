"""Кладёт файл в чат Помощника от имени Claude: картинка, видео, pdf и т. д.

    SUPABASE_URL=… SUPABASE_SERVICE_KEY=… python -I send_file.py файл [подпись]

Файл уходит в приватный бакет assistant, в папку владельца чата (так его
открывает приложение), и сообщение с вложением появляется в Помощнике.
Ключ проще передать через inbox.ps1 -Action reply -File ….
"""
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
LIMIT = 25 * 1024 * 1024  # file_size_limit бакета


def call(method, path, data=None, headers=None):
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header('apikey', KEY)
    req.add_header('Authorization', 'Bearer ' + KEY)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:300]


def main(path, caption):
    size = os.path.getsize(path)
    if size > LIMIT:
        sys.exit(f'файл {size // 1024 // 1024} МБ, лимит бакета 25 МБ')
    status, rows = call('GET', '/rest/v1/assistant_owner?select=profile_id')
    if status != 200 or not rows:
        sys.exit(f'не нашёл владельца чата: {status} {rows}')
    owner = rows[0]['profile_id']
    ext = os.path.splitext(path)[1].lower() or '.bin'
    remote = f'{owner}/claude_{int(time.time() * 1000)}{ext}'
    mime = mimetypes.guess_type(path)[0] or 'application/octet-stream'
    with open(path, 'rb') as f:
        status, resp = call('POST', f'/storage/v1/object/assistant/{remote}', f.read(),
                            {'Content-Type': mime})
    if status not in (200, 201):
        sys.exit(f'файл не загрузился: {status} {resp}')
    row = {'from_user': False, 'body': caption or None, 'attachment_path': remote}
    status, resp = call('POST', '/rest/v1/assistant_messages', json.dumps(row).encode(),
                        {'Content-Type': 'application/json', 'Prefer': 'return=minimal'})
    if status not in (200, 201, 204):
        sys.exit(f'сообщение не легло: {status} {resp}')
    print('Файл отправлен.')


main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '')
