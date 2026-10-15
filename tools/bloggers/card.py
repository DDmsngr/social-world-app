"""Карточка поста виртуального автора: заголовок крупно, фото в арке, подпись.

    python -I card.py --photo фото.jpg --title "Сочинский *дендрарий* в Хосте" \
        --author "Соня Прибрежная" --credit "Фото: Автор, CC BY-SA" --out card.png

Слова в *звёздочках* красятся акцентным цветом автора. Фото и текст
берутся из открытых источников и проверяются до карточки: сама карточка
ничего не добавляет от себя, кроме подписи «ChaWo · ИИ-автор».
"""
import argparse
import re

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1350
INK = (244, 242, 250)
DIM = (150, 146, 168)
# Фирменный цвет каждого автора: акцент в заголовке и тёмный фон в тон ему.
BRAND = {
    'sonya': ((156, 139, 224), (22, 19, 32)),   # сиреневый
    'mark': ((226, 112, 172), (32, 18, 28)),    # малиновый
    'ilya': ((96, 152, 238), (16, 22, 36)),     # синий
    'tikhon': ((242, 164, 72), (33, 25, 16)),   # оранжевый
    'vera': ((228, 108, 96), (34, 19, 18)),     # терракотовый
    'artem': ((72, 198, 204), (14, 29, 32)),    # бирюзовый
}
FONT = r'C:\Windows\Fonts\bahnschrift.ttf'


def font(size, weight='Bold'):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def tokens(title):
    """[(слово, акцент?)] из строки с *выделением*."""
    out = []
    glue = False  # часть без пробела после выделенного слова («*слово*:») клеится к нему
    for part in re.split(r'(\*[^*]+\*)', title):
        if not part:
            continue
        accent = part.startswith('*')
        words = part.strip('*').split()
        if glue and words and not part[0].isspace() and not accent:
            prev, was_accent = out.pop()
            out.append((prev + words.pop(0), was_accent))
        for word in words:
            out.append((word, accent))
        glue = accent
    return out


def layout(draw, words, fnt, width):
    lines, line, used = [], [], 0
    space = draw.textlength(' ', font=fnt)
    for word, accent in words:
        w = draw.textlength(word, font=fnt)
        if line and used + space + w > width:
            lines.append(line)
            line, used = [], 0
        used += (space if line else 0) + w
        line.append((word, accent))
    if line:
        lines.append(line)
    return lines


def render(photo, title, author, credit, brand, out):
    accent, bg = brand
    img = Image.new('RGB', (W, H), bg)
    d = ImageDraw.Draw(img)

    # Заголовок: подбираем кегль, чтобы влез в три строки.
    words = tokens(title.upper())
    size = 92
    while size > 52:
        fnt = font(size)
        lines = layout(d, words, fnt, W - 140)
        if len(lines) <= 3:
            break
        size -= 6
    y = 70
    for line in lines:
        total = sum(d.textlength(w, font=fnt) for w, _ in line) + d.textlength(' ', font=fnt) * (len(line) - 1)
        x = (W - total) / 2
        for word, is_accent in line:
            d.text((x, y), word, font=fnt, fill=accent if is_accent else INK)
            x += d.textlength(word, font=fnt) + d.textlength(' ', font=fnt)
        y += int(size * 1.12)

    # Разделитель с подписью автора по центру.
    y += 24
    label = f'ChaWo · {author}'
    lf = font(26, 'Bold')
    lw = d.textlength(label, font=lf)
    pad = 22
    x0, x1 = (W - lw) / 2 - pad, (W + lw) / 2 + pad
    mid = y + 20
    d.line([(70, mid), (x0 - 18, mid)], fill=INK, width=3)
    d.line([(x1 + 18, mid), (W - 70, mid)], fill=INK, width=3)
    d.rounded_rectangle([x0, y, x1, y + 40], radius=6, fill=INK)
    d.text(((W - lw) / 2, y + 4), label, font=lf, fill=bg)
    top = y + 40 + 40

    # Фото в арке.
    pw, ph = W - 160, H - top - 70
    src = Image.open(photo).convert('RGB')
    scale = max(pw / src.width, ph / src.height)
    src = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
    left, upper = (src.width - pw) // 2, (src.height - ph) // 2
    src = src.crop((left, upper, left + pw, upper + ph))
    mask = Image.new('L', (pw, ph), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, pw, ph], radius=28, fill=255)
    md.ellipse([0, 0, pw, pw], fill=255)
    md.rectangle([0, pw // 2, pw, ph], fill=255)
    md.rounded_rectangle([0, pw // 2, pw, ph], radius=28, fill=255)
    # верх арки — полукруг, а не прямоугольник
    top_cut = Image.new('L', (pw, ph), 0)
    cd = ImageDraw.Draw(top_cut)
    cd.ellipse([0, 0, pw, pw], fill=255)
    cd.rounded_rectangle([0, pw // 2, pw, ph], radius=28, fill=255)
    img.paste(src, (80, top), top_cut)

    # Подпись автора фото вертикально у правого края.
    if credit:
        cf = font(18, 'Regular')
        txt = credit if len(credit) < 70 else credit[:67] + '…'
        tw = int(d.textlength(txt, font=cf)) + 10
        strip = Image.new('RGBA', (tw, 28), (0, 0, 0, 0))
        ImageDraw.Draw(strip).text((0, 2), txt, font=cf, fill=DIM + (255,))
        strip = strip.rotate(90, expand=True)
        img.paste(strip, (W - 62, top + ph - strip.height - 20), strip)

    img.save(out)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--photo', required=True)
    p.add_argument('--title', required=True)
    p.add_argument('--author', required=True)
    p.add_argument('--credit', default='')
    p.add_argument('--key', default='sonya', help='ключ автора для цвета акцента')
    p.add_argument('--out', required=True)
    a = p.parse_args()
    render(a.photo, a.title, a.author, a.credit, BRAND.get(a.key, BRAND['sonya']), a.out)


if __name__ == '__main__':
    main()
