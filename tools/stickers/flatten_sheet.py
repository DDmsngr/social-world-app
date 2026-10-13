"""Лист на светлом фоне с клетчатой «прозрачностью» → лист на маджентовом фоне,
как ждёт add_pack.py.

У таких листов белая кайма стикера почти не отличается от фона, поэтому
ключом по цвету её не вырезать. Вместо этого берём саму фигуру (всё заметно
темнее светлого фона), заливаем дыры и обводим заново ровной белой каймой.

    python -I flatten_sheet.py вход.png выход.png [толщина каймы, px; 8 держит соседей раздельно]
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def flatten(src, dst, ring=8, dark=215):
    rgb = np.asarray(Image.open(src).convert('RGB')).astype(np.uint8)
    body = rgb.min(axis=2) < dark
    body = ndi.binary_opening(body, iterations=1)
    body = ndi.binary_closing(body, iterations=4)
    body = ndi.binary_fill_holes(body)
    # убираем мусор клетки: мелкие островки вне фигур
    lab, n = ndi.label(body)
    if n:
        areas = ndi.sum(body, lab, np.arange(1, n + 1))
        for i, a in enumerate(areas, 1):
            if a < 400:
                body[lab == i] = False
    yy, xx = np.ogrid[-ring:ring + 1, -ring:ring + 1]
    disk = (xx * xx + yy * yy) <= ring * ring
    sticker = ndi.binary_dilation(body, structure=disk)
    sticker = ndi.binary_fill_holes(sticker)
    out = np.empty_like(rgb)
    out[:] = (255, 0, 255)
    out[sticker] = (255, 255, 255)
    out[body] = rgb[body]
    # мягкая кромка тела: пиксели рядом с границей тела берём как есть,
    # но светлые пиксели (старая кайма) в пределах каймы — белые
    near = ndi.binary_dilation(body, iterations=3) & ~body
    light = rgb.min(axis=2) >= dark
    out[near & light] = (255, 255, 255)
    Image.fromarray(out, 'RGB').save(dst)


if __name__ == '__main__':
    flatten(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 8)
