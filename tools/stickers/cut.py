"""Нарезка листов 7x5 со смайлами/стикерами на отдельные RGBA-картинки.

Фон листа — плоский однотонный цвет (маджента или ярко-розовый). Фон вырезается
по расстоянию до цвета фона; кромка очищается от цветной каймы. Стикеры
привязываются к ячейкам сетки по центру самого большого куска, мелкие детали
(конфетти, сердечки, искры) — к ближайшему большому куску.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

COLS, ROWS = 7, 5
CANVAS = 512
FIT = 470  # самый крупный стикер пака занимает столько px из 512


def load(path):
    return np.asarray(Image.open(path).convert('RGB')).astype(np.float32)


def bg_color(img):
    parts = [img[:6].reshape(-1, 3), img[-6:].reshape(-1, 3),
             img[:, :6].reshape(-1, 3), img[:, -6:].reshape(-1, 3)]
    return np.median(np.concatenate(parts), axis=0)


def key(img, thr, band=3):
    bg = bg_color(img)
    dist = np.linalg.norm(img - bg, axis=2)
    is_bg = dist <= thr
    # крошечные «островки» цвета фона внутри фигуры тоже фон, но не шум в 1-2 px
    lab, n = ndi.label(is_bg)
    if n:
        sizes = ndi.sum(is_bg, lab, index=np.arange(1, n + 1))
        tiny = np.isin(lab, 1 + np.where(sizes < 6)[0])
        is_bg &= ~tiny
    fg = ~is_bg
    depth = ndi.distance_transform_edt(fg)  # расстояние до ближайшего фона, px
    # Кромка: альфа плавно растёт на ширине ~1,5 px от края фигуры. Это
    # детерминированная лесенка без «зубцов» (раньше альфа считалась по цвету
    # соседей и давала пунктир по контуру).
    alpha = np.where(fg, np.clip((depth - 0.3) / 1.4, 0, 1), 0).astype(np.float32)
    out = img.copy()
    edge = fg & (depth <= 2.2)
    # цвет кромки берём с «кольца» контура на глубине 2,5-4,5 px: там уже нет
    # примеси фона, но это ещё сам контур, а не заливка
    ring = fg & (depth >= 2.5) & (depth <= 4.5)
    d2, idx = ndi.distance_transform_edt(~ring, return_indices=True)
    nearest = img[idx[0], idx[1]]
    ok = edge & (d2 <= 5)
    out[ok] = nearest[ok]
    # тонкие детали без кольца: мягкий ключ и обратное смешивание
    thin = edge & ~ok
    a_soft = np.clip((dist - thr * 0.5) / (thr * 1.5), 0, 1)
    alpha[thin] = np.maximum(alpha[thin], a_soft[thin])
    m = thin & (alpha > 0.02)
    out[m] = np.clip((img[m] - (1 - alpha[m, None]) * bg) / alpha[m, None], 0, 255)
    return out, alpha


def assign(alpha, shape):
    h, w = shape
    mask = alpha > 0.3
    lab, n = ndi.label(mask, structure=np.ones((3, 3)))
    if n == 0:
        return lab, {}
    idxs = np.arange(1, n + 1)
    areas = ndi.sum(mask, lab, idxs)
    cents = ndi.center_of_mass(mask, lab, idxs)
    cell_area = (w / COLS) * (h / ROWS)
    big = [i for i, a in zip(idxs, areas) if a >= 0.03 * cell_area]
    big_mask = np.isin(lab, big)
    # к какому большому куску ближе каждая мелочь
    _, near = ndi.distance_transform_edt(~big_mask, return_indices=True)
    cells = {}
    owner = {}
    for i in big:
        cy, cx = cents[i - 1]
        c = min(COLS - 1, int(cx / (w / COLS)))
        r = min(ROWS - 1, int(cy / (h / ROWS)))
        owner[i] = (r, c)
    for i, a in zip(idxs, areas):
        if i in owner:
            cells.setdefault(owner[i], []).append(i)
        elif a >= 8:
            ys, xs = np.where(lab == i)
            k = len(ys) // 2
            ny, nx = near[0][ys[k], xs[k]], near[1][ys[k], xs[k]]
            j = lab[ny, nx]
            if j in owner:
                cells.setdefault(owner[j], []).append(i)
    return lab, cells


def premul_resize(rgba, scale):
    a = rgba[..., 3:4] / 255.0
    pm = np.concatenate([rgba[..., :3] * a, rgba[..., 3:4]], axis=2).astype(np.float32)
    h, w = pm.shape[:2]
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    pm = cv2.resize(pm, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
    al = np.clip(pm[..., 3:4], 0, 255)
    rgb = np.where(al > 0.5, pm[..., :3] / np.maximum(al / 255.0, 1e-3), 0)
    return np.clip(np.concatenate([rgb, al], axis=2), 0, 255).astype(np.uint8)


def cut(path, thr, names, outdir, debug=None):
    img = load(path)
    h, w = img.shape[:2]
    rgb, alpha = key(img, thr)
    lab, cells = assign(alpha, (h, w))
    items = {}
    for (r, c), comps in cells.items():
        keep = np.isin(lab, comps)
        keep = ndi.binary_dilation(keep, iterations=3) & (alpha > 0)
        a = np.where(keep, alpha, 0)
        ys, xs = np.where(a > 0.02)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        rgba = np.dstack([rgb, a * 255])[y0:y1, x0:x1]
        items[(r, c)] = rgba
    missing = [(r, c) for r in range(ROWS) for c in range(COLS) if (r, c) not in items]
    biggest = max(max(v.shape[:2]) for v in items.values())
    scale = FIT / biggest
    os.makedirs(outdir, exist_ok=True)
    thumbs = {}
    for (r, c), rgba in sorted(items.items()):
        name = names[r * COLS + c]
        up = premul_resize(rgba, scale)
        canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
        im = Image.fromarray(up, 'RGBA')
        canvas.paste(im, ((CANVAS - im.width) // 2, (CANVAS - im.height) // 2), im)
        fname = f'{r * COLS + c + 1:02d}_{name}.webp'
        canvas.save(os.path.join(outdir, fname), 'WEBP', quality=92, alpha_quality=100, method=6)
        thumbs[(r, c)] = canvas
    if debug:
        dbg = img.copy().astype(np.uint8)
        for k in range(1, COLS):
            dbg[:, int(k * w / COLS)] = (0, 255, 0)
        for k in range(1, ROWS):
            dbg[int(k * h / ROWS), :] = (0, 255, 0)
        Image.fromarray(dbg).save(debug)
    return thumbs, missing, scale


def preview(thumbs, path, bgcol, size=160):
    sheet = Image.new('RGB', (COLS * size, ROWS * size), bgcol)
    for (r, c), im in thumbs.items():
        t = im.resize((size, size), Image.LANCZOS)
        sheet.paste(t, (c * size, r * size), t)
    sheet.save(path)


if __name__ == '__main__':
    cfg = json.load(open(sys.argv[1]))
    root = cfg['out']
    for pack in cfg['packs']:
        outdir = os.path.join(root, pack['dir'])
        thumbs, missing, scale = cut(pack['src'], pack['thr'], pack['names'], outdir,
                                     debug=os.path.join(root, pack['dir'] + '_grid.png'))
        print(pack['dir'], 'stickers', len(thumbs), 'missing', missing, 'scale %.2f' % scale)
        preview(thumbs, os.path.join(root, pack['dir'] + '_light.png'), (255, 255, 255))
        preview(thumbs, os.path.join(root, pack['dir'] + '_dark.png'), (28, 28, 32))
