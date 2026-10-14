"""Заводит виртуальных авторов ChaWo (миграция 0090). Повторный запуск безопасен.

    SUPABASE_URL=… SUPABASE_SERVICE_KEY=… python -I create_authors.py

Для каждого автора: пользователь в GoTrue (служебный адрес, случайный пароль,
которого никто не знает — входа в аккаунт нет), аватар в публичном бакете
avatars/system, профиль (имя, ник, описание с меткой «Виртуальный автор»),
запись в bot_authors. Ключ проще передать через create_authors.ps1.
"""
import json
import os
import secrets
import sys
import urllib.error
import urllib.request

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
HERE = os.path.dirname(os.path.abspath(__file__))
AVATARS = os.environ.get('AVATARS_DIR', r'D:\temp\bloggers\avatars')

LABEL = 'Виртуальный автор ChaWo · ведёт редакция'

AUTHORS = [
    ('sonya', 'sonya_gid', 'Соня Прибрежная', 'Места, тропы и смотровые Сочи: как добраться и когда ехать.'),
    ('mark', 'mark_afisha', 'Марк Афишин', 'Выставки, премьеры и фестивали: что стоит увидеть.'),
    ('ilya', 'ilya_facts', 'Илья Горский', 'Интересные факты с источниками, без шока и приукрас.'),
    ('tikhon', 'tikhon_zveri', 'Тихон Зверев', 'Животные: дельфины и птицы Сочи, приюты, как помочь.'),
    ('vera', 'vera_kuhnya', 'Вера Кухарина', 'Южная и кавказская кухня: рецепты и что попробовать.'),
    ('artem', 'artem_volna', 'Артём Волнов', 'Море, горы и погода простым языком, безопасно и бодро.'),
]


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
    for key, nick, name, about in AUTHORS:
        status, rows = call('GET', f'/rest/v1/profiles?username=eq.{nick}&select=id')
        if status == 200 and rows:
            pid = rows[0]['id']
            print(nick, 'уже есть')
        else:
            status, user = call(
                'POST', '/auth/v1/admin/users',
                json.dumps({
                    'email': f'bot.{nick}@id.socialworld.internal',
                    'password': secrets.token_urlsafe(32),
                    'email_confirm': True,
                    'user_metadata': {'bot': True},
                }).encode(),
                {'Content-Type': 'application/json'},
            )
            if status not in (200, 201):
                sys.exit(f'{nick}: аккаунт не создался: {status} {user}')
            pid = user['id']

        path = f'system/{nick}.png'
        with open(os.path.join(AVATARS, f'{key}.png'), 'rb') as f:
            status, resp = call('POST', f'/storage/v1/object/avatars/{path}', f.read(),
                                {'Content-Type': 'image/png', 'x-upsert': 'true'})
        if status not in (200, 201):
            sys.exit(f'{nick}: аватар не загрузился: {status} {resp}')

        patch = {
            'display_name': name,
            'username': nick,
            'bio': f'{LABEL}\n{about}',
            'city': 'Сочи',
            'avatar_url': f'{URL}/storage/v1/object/public/avatars/{path}',
            'onboarded_at': '2026-10-14T00:00:00Z',
        }
        status, resp = call('PATCH', f'/rest/v1/profiles?id=eq.{pid}', json.dumps(patch).encode(),
                            {'Content-Type': 'application/json', 'Prefer': 'return=minimal'})
        if status not in (200, 204):
            sys.exit(f'{nick}: профиль не обновился: {status} {resp}')
        status, resp = call('POST', '/rest/v1/bot_authors', json.dumps({'profile_id': pid, 'topic': about}).encode(),
                            {'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates,return=minimal'})
        if status not in (200, 201, 204):
            sys.exit(f'{nick}: запись в bot_authors не легла: {status} {resp}')
        print(f'{nick}: готов ({pid})')


main()
