"""Аватарка канала «Котики» (chawo_cats): кошачья мордочка на тёплом градиенте.

    python -I make_cats_avatar.py cats_avatar.png

Рисуется эмодзи 😺 шрифтом Segoe UI Emoji (Windows). Готовый файл лежит в
публичном бакете avatars по пути system/chawo_cats.png, ссылка — в
supabase/seed/system_channel_cats.sql.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SIZE = 512
EMOJI = '\U0001F63A'


def render(path):
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    t = (x + y) / (2 * SIZE)
    peach = np.array([255, 196, 140], float)
    lilac = np.array([196, 150, 235], float)
    pixels = (peach * (1 - t[..., None]) + lilac * t[..., None]).astype(np.uint8)
    image = Image.fromarray(pixels, 'RGB').convert('RGBA')
    font = ImageFont.truetype('C:/Windows/Fonts/seguiemj.ttf', 300)
    draw = ImageDraw.Draw(image)
    box = draw.textbbox((0, 0), EMOJI, font=font, embedded_color=True)
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text(((SIZE - w) / 2 - box[0], (SIZE - h) / 2 - box[1]), EMOJI, font=font, embedded_color=True)
    image.convert('RGB').save(path)


if __name__ == '__main__':
    render(sys.argv[1] if len(sys.argv) > 1 else 'cats_avatar.png')
