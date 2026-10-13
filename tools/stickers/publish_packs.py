"""Публикует паки стикеров из tools/stickers/packs/ в магазин ChaWo.

Пак — папка packs/<id>/ с pack.json (название, описание, порядок стикеров,
слова для поиска) и картинками <ключ>.webp 512×512 с прозрачностью. Для
каждого стикера делается превью 192 px (для сетки магазина и панели), файлы
уходят в публичный бакет stickers, строки — в sticker_packs / stickers,
семейства эмоций — в sticker_families. Запуск повторяемый: файлы
перезаписываются, строки обновляются по id.

Id стикера (`<пак>.<ключ>`) уходит в сообщения навсегда: ключ не
переименовывать и стикер не удалять из pack.json (удаление скрипт
отклонит — снимите пак с публикации, status = "archived"). Перерисовали
картинки — поднимите version в pack.json, чтобы телефоны сбросили кеш.

    SUPABASE_URL=https://… SUPABASE_SERVICE_KEY=… python -I publish_packs.py [пак ...]
    python -I publish_packs.py --check            # только проверить папки, без сети

Ключ сервера проще всего передать через publish.ps1 (читает его по ssh и на
экран не выводит).
"""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS = os.path.join(HERE, 'packs')
BUCKET = 'stickers'
THUMB = 192
KEY_RE = re.compile(r'^[a-z0-9_]{1,48}$')
PACK_RE = re.compile(r'^[a-z0-9_]{1,32}$')
STATUSES = {'draft', 'review', 'published', 'archived'}


def load_pack(pid):
    folder = os.path.join(PACKS, pid)
    meta = json.load(open(os.path.join(folder, 'pack.json'), encoding='utf-8-sig'))
    assert meta['id'] == pid and PACK_RE.match(pid), f'{pid}: id пака'
    assert meta.get('status', 'draft') in STATUSES, f'{pid}: status'
    keys = [s['key'] for s in meta['stickers']]
    assert len(keys) == len(set(keys)), f'{pid}: повтор ключа'
    for s in meta['stickers']:
        assert KEY_RE.match(s['key']), f'{pid}.{s["key"]}: ключ'
        assert s['title'] and s['emoji'], f'{pid}.{s["key"]}: название и эмодзи'
        path = os.path.join(folder, s['key'] + '.webp')
        assert os.path.isfile(path), f'{pid}.{s["key"]}: нет картинки'
        with Image.open(path) as im:
            assert im.mode == 'RGBA', f'{pid}.{s["key"]}: нет прозрачности ({im.mode})'
            assert im.size[0] <= 1024 and im.size[1] <= 1024, f'{pid}.{s["key"]}: больше 1024 px'
    extra = {f[:-5] for f in os.listdir(folder) if f.endswith('.webp')} - set(keys)
    assert not extra, f'{pid}: картинки без строки в pack.json: {sorted(extra)}'
    return folder, meta


def thumb_bytes(path):
    with Image.open(path) as im:
        im = im.convert('RGBA')
        im.thumbnail((THUMB, THUMB), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, 'WEBP', quality=88, alpha_quality=100, method=6)
        return buf.getvalue()


class Api:
    def __init__(self, url, key):
        self.url = url.rstrip('/')
        self.key = key

    def _call(self, method, path, body=None, headers=None):
        req = urllib.request.Request(self.url + path, data=body, method=method)
        req.add_header('apikey', self.key)
        req.add_header('Authorization', 'Bearer ' + self.key)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'{method} {path}: {e.code} {e.read().decode("utf-8", "replace")}') from None

    def upload(self, path, data):
        self._call('POST', f'/storage/v1/object/{BUCKET}/{path}', data,
                   {'Content-Type': 'image/webp', 'x-upsert': 'true', 'Cache-Control': 'max-age=31536000'})

    def upsert(self, table, rows, conflict):
        self._call('POST', f'/rest/v1/{table}?on_conflict={conflict}',
                   json.dumps(rows, ensure_ascii=False).encode('utf-8'),
                   {'Content-Type': 'application/json',
                    'Prefer': 'resolution=merge-duplicates,return=minimal'})

    def patch(self, path, values):
        self._call('PATCH', '/rest/v1/' + path, json.dumps(values, ensure_ascii=False).encode('utf-8'),
                   {'Content-Type': 'application/json', 'Prefer': 'return=minimal'})

    def select(self, path):
        return self._call('GET', '/rest/v1/' + path)


def publish(api, pid):
    folder, meta = load_pack(pid)
    existing = {r['key'] for r in api.select(f'stickers?select=key&pack_id=eq.{pid}')}
    gone = existing - {s['key'] for s in meta['stickers']}
    if gone:
        raise SystemExit(f'{pid}: из pack.json пропали {sorted(gone)} — стикеры не удаляются, '
                         'снимите пак с публикации или верните строки')
    rows = []
    for i, s in enumerate(meta['stickers']):
        src = os.path.join(folder, s['key'] + '.webp')
        image = f'{pid}/{s["key"]}.webp'
        thumb = f'{pid}/thumb/{s["key"]}.webp'
        with open(src, 'rb') as fh:
            api.upload(image, fh.read())
        api.upload(thumb, thumb_bytes(src))
        with Image.open(src) as im:
            w, h = im.size
        rows.append({
            'id': f'{pid}.{s["key"]}', 'pack_id': pid, 'key': s['key'], 'position': i,
            'image_path': image, 'thumb_path': thumb, 'width': w, 'height': h,
            'title': s['title'], 'emoji': s['emoji'],
            'synonyms': s.get('synonyms', []), 'emotions': s.get('emotions', []),
        })
    cover_key = meta.get('cover') or meta['stickers'][0]['key']
    # Сначала пак (на него ссылаются стикеры), статус — после стикеров: пак
    # не появится в магазине пустым.
    pack = {
        'id': pid, 'title': meta['title'], 'description': meta.get('description'),
        'publisher': meta.get('publisher', 'Команда ChaWo'), 'category': meta.get('category'),
        'cover_path': f'{pid}/thumb/{cover_key}.webp', 'version': meta.get('version', 1),
        'is_default': meta.get('is_default', False), 'sort_order': meta.get('sort_order', 0),
    }
    api.upsert('sticker_packs', [{**pack, 'status': 'draft'}] if not existing else [pack], 'id')
    api.upsert('stickers', rows, 'id')
    api.patch(f'sticker_packs?id=eq.{pid}', {'status': meta.get('status', 'draft')})
    print(f'{pid}: {len(rows)} стикеров, статус {meta.get("status", "draft")}')


def main(argv):
    names = [a for a in argv if not a.startswith('--')]
    packs = names or sorted(d for d in os.listdir(PACKS) if os.path.isdir(os.path.join(PACKS, d)))
    families = json.load(open(os.path.join(PACKS, 'families.json'), encoding='utf-8-sig'))
    for pid in packs:
        _, meta = load_pack(pid)
        for s in meta['stickers']:
            for fam in s.get('emotions', []):
                assert fam in families, f'{pid}.{s["key"]}: неизвестное семейство {fam}'
    if '--check' in argv:
        print('ok', len(packs), 'паков')
        return
    api = Api(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SERVICE_KEY'])
    api.upsert('sticker_families', [{'key': k, 'words': v} for k, v in families.items()], 'key')
    for pid in packs:
        publish(api, pid)


if __name__ == '__main__':
    main(sys.argv[1:])
