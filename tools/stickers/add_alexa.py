"""Пак «Алекса»: лист 6x4 на маджентовом фоне → packs/alexa/*.webp и стикеры
в packs/alexa/pack.json. Дальше пак уходит в магазин через publish.ps1.

Остальные паки не трогаются, «alexa» при повторном запуске пересобирается.
Запуск: python3 -I add_alexa.py sheets/alexa.png packs [папка для превью]
"""
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from scipy import ndimage as ndi  # noqa: E402

import cut  # noqa: E402

cut.COLS, cut.ROWS = 6, 4
THR = 90

# ключ, название, эмодзи-заменитель, семейства эмоций (первое главное), синонимы
STICKERS = [
    ('wave', 'привет', '👋', ['greet', 'joy'], ['привет', 'пока', 'здравствуй', 'машу', 'алекса']),
    ('laugh', 'смеюсь', '😂', ['joy'], ['смех', 'ржу', 'хаха', 'весело', 'радуюсь']),
    ('smirk_think', 'хитрая мысль', '🤔', ['think', 'cool'], ['думаю', 'хмм', 'интересно', 'прикидываю']),
    ('shocked', 'ничего себе', '😲', ['surprise'], ['вау', 'ого', 'шок', 'не может быть']),
    ('grumpy', 'обиделась', '😒', ['anger', 'sad'], ['дуюсь', 'обида', 'недовольна', 'бука']),
    ('cry', 'плачу', '😭', ['sad'], ['слёзы', 'рыдаю', 'грустно', 'горько']),
    ('queen', 'королева', '👑', ['cool', 'joy'], ['корона', 'лучшая', 'царица', 'я молодец']),
    ('shy', 'смущаюсь', '🥰', ['love', 'joy'], ['стесняюсь', 'мило', 'краснею', 'приятно']),
    ('cheer', 'ура', '🎉', ['party', 'joy'], ['победа', 'получилось', 'урааа', 'праздник']),
    ('question', 'а что?', '❓', ['think'], ['вопрос', 'почему', 'не понимаю', 'как так']),
    ('doubt', 'сомневаюсь', '🧐', ['think', 'anger'], ['не верю', 'подозрительно', 'сомнение', 'серьёзно']),
    ('cat_hug', 'обнимаю кота', '🐱', ['love', 'friend'], ['кот', 'котик', 'уют', 'обнимашки', 'нежность']),
    ('sleep', 'сплю', '😴', ['tired'], ['сон', 'спокойной ночи', 'спать', 'подушка']),
    ('idea', 'идея', '💡', ['think', 'joy'], ['придумала', 'лампочка', 'эврика', 'решение']),
    ('kiss', 'воздушный поцелуй', '😘', ['love'], ['целую', 'чмок', 'люблю', 'поцелуй']),
    ('stop', 'стоп', '✋', ['anger'], ['хватит', 'не надо', 'нет', 'остановись']),
    ('bored', 'устала', '😩', ['tired', 'anger'], ['скучно', 'бесит', 'лень', 'надоело']),
    ('dreamy', 'мечтаю', '🥹', ['love', 'joy'], ['мечта', 'умиление', 'милота', 'хочу']),
    ('facepalm', 'фейспалм', '🤦', ['sad', 'anger'], ['позор', 'ну зачем', 'ужас', 'стыдно']),
    ('peek_door', 'выглядываю', '🚪', ['think', 'fear'], ['подглядываю', 'можно?', 'за дверью', 'прячусь']),
    ('plate', 'угощаю', '🍽️', ['food', 'friend'], ['еда', 'готово', 'за стол', 'приятного аппетита']),
    ('rain_sad', 'грустный дождь', '🌧️', ['sad', 'weather'], ['дождь', 'тоска', 'пасмурно', 'печаль']),
    ('victory', 'победа', '🙌', ['joy', 'energy'], ['да', 'ура', 'получилось', 'сделала', 'бодрость']),
    ('cocoa', 'какао', '☕', ['food', 'joy'], ['какао', 'уют', 'тепло', 'сладкое', 'кофе']),
]


# Стикеры, которые есть на листе, но в пак не идут (позиции в сетке остаются).
EXCLUDE = {'victory'}


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
    """Убирает мелкие пылинки далеко от самой фигуры (след от соседней ячейки)."""
    lab, n = ndi.label(a > 0.3, structure=np.ones((3, 3)))
    if n < 2:
        return a
    areas = ndi.sum(a > 0.3, lab, np.arange(1, n + 1))
    main = 1 + int(np.argmax(areas))
    gap = ndi.distance_transform_edt(lab != main)
    for i in range(1, n + 1):
        comp = lab == i
        on_border = comp[:12].any() or comp[-12:].any()  # обломок соседней ячейки
        if i == main or (areas[i - 1] >= max_area and not (on_border and areas[i - 1] < 400)):
            continue
        if gap[comp].min() > min_gap or on_border:
            a = np.where(comp, 0, a)
    return a


def cut_by_rows(sheet, names, outdir):
    """То же, что cut.cut, но лист обрабатывается полосами по одному ряду:
    целиком он съедает слишком много памяти. Масштаб общий на весь пак."""
    img = cut.load(sheet)
    h, w = img.shape[:2]
    band = h // cut.ROWS
    cols, rows = cut.COLS, cut.ROWS
    items = {}
    for r in range(rows):
        strip = img[r * band:(r + 1) * band]
        rgb, alpha = cut.key(strip, THR)
        rgb = despill(rgb, alpha)
        cut.ROWS = 1
        lab, cells = cut.assign(alpha, strip.shape[:2])
        cut.ROWS = rows
        for (_, c), comps in cells.items():
            keep = np.isin(lab, comps)
            keep = ndi.binary_dilation(keep, iterations=3) & (alpha > 0)
            a = drop_specks(np.where(keep, alpha, 0))
            ys, xs = np.where(a > 0.02)
            y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            items[(r, c)] = np.dstack([rgb[y0:y1, x0:x1], a[y0:y1, x0:x1] * 255])
        del strip, rgb, alpha, lab
    missing = [(r, c) for r in range(rows) for c in range(cols) if (r, c) not in items]
    scale = cut.FIT / max(max(v.shape[:2]) for v in items.values())
    os.makedirs(outdir, exist_ok=True)
    thumbs = {}
    for (r, c), rgba in sorted(items.items()):
        if names[r * cols + c] in EXCLUDE:
            continue
        up = cut.premul_resize(rgba, scale)
        canvas = Image.new('RGBA', (cut.CANVAS, cut.CANVAS), (0, 0, 0, 0))
        im = Image.fromarray(up, 'RGBA')
        canvas.paste(im, ((cut.CANVAS - im.width) // 2, (cut.CANVAS - im.height) // 2), im)
        fname = f'{r * cols + c + 1:02d}_{names[r * cols + c]}.webp'
        canvas.save(os.path.join(outdir, fname), 'WEBP', quality=92, alpha_quality=100, method=6)
        thumbs[(r, c)] = canvas
    return thumbs, missing, scale


def main(sheet, dst):
    assert len(STICKERS) == 24
    names = [s[0] for s in STICKERS]
    tmp = tempfile.mkdtemp(prefix='alexa_cut_')
    thumbs, missing, scale = cut_by_rows(sheet, names, tmp)
    assert not missing, f'не нашлись ячейки: {missing}'
    if len(sys.argv) > 3:  # превью на светлом и тёмном фоне для проверки глазами
        cut.preview(thumbs, os.path.join(sys.argv[3], 'alexa_light.png'), (255, 255, 255))
        cut.preview(thumbs, os.path.join(sys.argv[3], 'alexa_dark.png'), (28, 28, 32))
    out = os.path.join(dst, 'alexa')
    os.makedirs(out, exist_ok=True)
    for old in os.listdir(out):  # папку не удаляем: Windows может держать её открытой
        if old.endswith('.webp'):
            os.remove(os.path.join(out, old))
    for f in os.listdir(tmp):
        if f.endswith('.webp'):
            shutil.copy(os.path.join(tmp, f), os.path.join(out, f.split('_', 1)[1]))
    shutil.rmtree(tmp)

    # Описание пака для publish_packs.py: шапка сохраняется, стикеры — из
    # списка выше по порядку.
    path = os.path.join(out, 'pack.json')
    meta = json.load(open(path, encoding='utf-8')) if os.path.isfile(path) else {
        'id': 'alexa', 'title': 'Алекса', 'publisher': 'Команда ChaWo',
        'category': 'персонажи', 'status': 'draft', 'version': 1,
    }
    meta['stickers'] = [
        {'key': key, 'title': title, 'emoji': emoji, 'synonyms': extra, 'emotions': fams}
        for key, title, emoji, fams, extra in STICKERS
        if key not in EXCLUDE
    ]
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    print('ok', len(meta['stickers']), 'scale %.2f' % scale)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
