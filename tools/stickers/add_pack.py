"""Новый пак из листа: specs/<пак>.json → packs/<пак>/*.webp и pack.json.

Лист — сетка стикеров на плоском фоне (маджента #FF00FF). Фон вырезается,
розовая кайма с волос и одежды снимается, обломки соседних ячеек и пылинки
убираются, все стикеры масштабируются одним коэффициентом в 512×512 с
прозрачными полями. Лист режется полосами по ряду — целиком он не влезает в
память ноутбука.

    python -I add_pack.py specs/alexa.json [папка для превью]
    python -I add_pack.py specs/alexa.json --check   # только проверить спеку

Спека (см. specs/alexa.json):
    id, title, description, publisher, category, status, is_default,
    sort_order, version — шапка пака (уходит в pack.json как есть);
    sheet — путь к листу от этой папки; grid — [колонки, ряды]; thr — порог
    фона (90 подходит для мадженты); exclude — ключи, которые есть на листе,
    но в пак не идут; stickers — по одной строке на ячейку, слева направо и
    сверху вниз: key, title, emoji, emotions (семейства из packs/families.json,
    первое главное), synonyms. Пустая ячейка листа — строка с "key": null.

Дальше: проверить превью глазами и опубликовать (publish.ps1 <пак>).
"""
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from scipy import ndimage as ndi  # noqa: E402

import cut  # noqa: E402

HEADER = ('id', 'title', 'description', 'publisher', 'category', 'status',
          'is_default', 'sort_order', 'version', 'cover')
KEY_RE = re.compile(r'^[a-z0-9_]{1,48}$')


def despill(rgb, alpha, width=6):
    """Волосы и одежда на кромке набрали розового от маджентового фона.
    В пределах [width] px от края красный и синий не должны одновременно
    заметно превышать зелёный: срезаем синий и частично красный."""
    fg = alpha > 0.3
    depth = ndi.distance_transform_edt(fg)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    spill = fg & (depth <= width) & (b > g + 8) & (r > g + 8)
    m = np.minimum(r, b) - g
    out = rgb.copy()
    out[..., 2] = np.where(spill, g, b)
    out[..., 0] = np.where(spill, r - m * 0.6, r)
    out[..., 1] = np.where(spill, g + m * 0.3, g)
    return np.clip(out, 0, 255)


def drop_specks(a, max_area=60, min_gap=35):
    """Убирает мелкие пылинки далеко от фигуры и обломки соседней ячейки у
    верхней и нижней кромки полосы."""
    lab, n = ndi.label(a > 0.3, structure=np.ones((3, 3)))
    if n < 2:
        return a
    areas = ndi.sum(a > 0.3, lab, np.arange(1, n + 1))
    main = 1 + int(np.argmax(areas))
    gap = ndi.distance_transform_edt(lab != main)
    for i in range(1, n + 1):
        comp = lab == i
        on_border = comp[:12].any() or comp[-12:].any()
        if i == main or (areas[i - 1] >= max_area and not (on_border and areas[i - 1] < 400)):
            continue
        if gap[comp].min() > min_gap or on_border:
            a = np.where(comp, 0, a)
    return a


def cut_by_rows(sheet, cols, rows, thr):
    """Стикеры листа по ячейкам: {(ряд, колонка): RGBA}, масштаб общий."""
    img = cut.load(sheet)
    band = img.shape[0] // rows
    cut.COLS, cut.ROWS = cols, 1
    items = {}
    for r in range(rows):
        strip = img[r * band:(r + 1) * band]
        rgb, alpha = cut.key(strip, thr)
        rgb = despill(rgb, alpha)
        lab, cells = cut.assign(alpha, strip.shape[:2])
        for (_, c), comps in cells.items():
            keep = np.isin(lab, comps)
            keep = ndi.binary_dilation(keep, iterations=3) & (alpha > 0)
            a = drop_specks(np.where(keep, alpha, 0))
            ys, xs = np.where(a > 0.02)
            if len(ys) == 0:
                continue
            y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            items[(r, c)] = np.dstack([rgb[y0:y1, x0:x1], a[y0:y1, x0:x1] * 255])
        del strip, rgb, alpha, lab
    cut.ROWS = rows
    scale = cut.FIT / max(max(v.shape[:2]) for v in items.values())
    return items, scale


def render(rgba, scale):
    up = cut.premul_resize(rgba, scale)
    canvas = Image.new('RGBA', (cut.CANVAS, cut.CANVAS), (0, 0, 0, 0))
    im = Image.fromarray(up, 'RGBA')
    canvas.paste(im, ((cut.CANVAS - im.width) // 2, (cut.CANVAS - im.height) // 2), im)
    return canvas


def check_spec(spec):
    families = json.load(open(os.path.join(HERE, 'packs', 'families.json'), encoding='utf-8'))
    cols, rows = spec['grid']
    cells = spec['stickers']
    assert len(cells) == cols * rows, f'строк в stickers {len(cells)}, а ячеек {cols}×{rows}'
    keys = [s['key'] for s in cells if s.get('key')]
    assert len(keys) == len(set(keys)), 'повтор ключа'
    for s in cells:
        if not s.get('key'):
            continue
        assert KEY_RE.match(s['key']), f'ключ {s["key"]}: латиница, цифры, _'
        assert s.get('title') and s.get('emoji'), f'{s["key"]}: нужны title и emoji'
        assert s.get('emotions'), f'{s["key"]}: нужно хотя бы одно семейство эмоций'
        for f in s['emotions']:
            assert f in families, f'{s["key"]}: неизвестное семейство {f} (есть: {", ".join(families)})'
    for k in spec.get('exclude', []):
        assert k in keys, f'exclude: нет ключа {k}'
    assert os.path.isfile(os.path.join(HERE, spec['sheet'])), f'нет листа {spec["sheet"]}'


def main(argv):
    spec_path = argv[0]
    spec = json.load(open(spec_path, encoding='utf-8'))
    check_spec(spec)
    if '--check' in argv:
        print('ok', spec['id'])
        return
    pid = spec['id']
    cols, rows = spec['grid']
    exclude = set(spec.get('exclude', []))
    cells = spec['stickers']

    items, scale = cut_by_rows(os.path.join(HERE, spec['sheet']), cols, rows, spec.get('thr', 90))
    empty = [i for i, s in enumerate(cells) if s.get('key') and (i // cols, i % cols) not in items]
    assert not empty, f'на листе не нашлись ячейки {[cells[i]["key"] for i in empty]}'

    out = os.path.join(HERE, 'packs', pid)
    os.makedirs(out, exist_ok=True)
    for old in os.listdir(out):  # папку не удаляем: Windows может держать её открытой
        if old.endswith('.webp'):
            os.remove(os.path.join(out, old))
    thumbs = {}
    for i, s in enumerate(cells):
        if not s.get('key') or s['key'] in exclude:
            continue
        canvas = render(items[(i // cols, i % cols)], scale)
        canvas.save(os.path.join(out, s['key'] + '.webp'), 'WEBP', quality=92, alpha_quality=100, method=6)
        thumbs[(i // cols, i % cols)] = canvas

    meta = {k: spec[k] for k in HEADER if k in spec}
    meta.setdefault('publisher', 'Команда ChaWo')
    meta.setdefault('status', 'draft')
    meta.setdefault('version', 1)
    meta['stickers'] = [
        {'key': s['key'], 'title': s['title'], 'emoji': s['emoji'],
         'synonyms': s.get('synonyms', []), 'emotions': s['emotions']}
        for s in cells if s.get('key') and s['key'] not in exclude
    ]
    with open(os.path.join(out, 'pack.json'), 'w', encoding='utf-8') as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)

    previews = [a for a in argv[1:] if not a.startswith('--')]
    if previews:
        cut.COLS, cut.ROWS = cols, rows
        cut.preview(thumbs, os.path.join(previews[0], f'{pid}_light.png'), (255, 255, 255))
        cut.preview(thumbs, os.path.join(previews[0], f'{pid}_dark.png'), (28, 28, 32))
    print('ok', pid, len(meta['stickers']), 'scale %.2f' % scale)


if __name__ == '__main__':
    main(sys.argv[1:])
