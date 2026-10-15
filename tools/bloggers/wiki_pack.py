"""Материал для постов из ru.wikipedia: вступление статьи, главное фото с Commons, лицензия.

    python -I wiki_pack.py ПАПКА "Статья 1" "Статья 2" …

На каждую статью в ПАПКЕ ложатся NN.txt (адрес и вступление, чтобы прочитать
перед написанием), NN.jpg (фото 1280 px) и NN.json (подпись автора фото).
Берутся только фото с Wikimedia Commons: несвободные картинки (fair use) лежат
на ru.wikipedia и пропускаются. Статья без свободного фото пропускается.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

UA = {'User-Agent': 'ChaWoEditorial/1.0 (https://deepdrift.tech; editorial@chawo)'}


def get(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40))


def strip(s):
    return re.sub('<[^>]+>', '', s or '').strip()


def pack(title, out, n):
    q = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'prop': 'extracts|pageimages|info',
                                'explaintext': 1, 'titles': title,
                                'piprop': 'original', 'inprop': 'url', 'redirects': 1})
    page = next(iter(get('https://ru.wikipedia.org/w/api.php?' + q)['query']['pages'].values()))
    if 'missing' in page:
        return f'{title}: статьи нет'
    src = (page.get('original') or {}).get('source', '')
    if '/wikipedia/commons/' not in src:
        return f'{title}: нет свободного фото на Commons'
    name = urllib.parse.unquote(src.split('?')[0].rsplit('/', 1)[-1])
    q = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'prop': 'imageinfo',
                                'iiprop': 'url|extmetadata|size', 'iiurlwidth': 1280, 'titles': 'File:' + name})
    info = next(iter(get('https://commons.wikimedia.org/w/api.php?' + q)['query']['pages'].values()))['imageinfo'][0]
    m = info['extmetadata']
    lic = strip(m.get('LicenseShortName', {}).get('value'))
    if re.search(r'fair|non-?free|nc|nd', lic, re.I) and not re.search(r'public|cc0|cc by(-sa)?', lic, re.I):
        return f'{title}: лицензия {lic} не подходит'
    artist = strip(m.get('Artist', {}).get('value')) or 'автор не указан'
    req = urllib.request.Request(info['thumburl'], headers=UA)
    with open(os.path.join(out, f'{n:02d}.jpg'), 'wb') as f:
        f.write(urllib.request.urlopen(req, timeout=60).read())
    with open(os.path.join(out, f'{n:02d}.json'), 'w', encoding='utf-8') as f:
        json.dump({'title': page['title'], 'url': page['fullurl'], 'artist': artist, 'license': lic,
                   'commons': info['descriptionurl']}, f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, f'{n:02d}.txt'), 'w', encoding='utf-8') as f:
        f.write(f"{page['title']}\n{page['fullurl']}\nФото: {artist}, {lic}\n\n{page.get('extract', '')}\n")
    return f'{n:02d} {page["title"]}: ок ({lic})'


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    start = len([x for x in os.listdir(out) if x.endswith('.json')]) + 1
    n = start
    for t in sys.argv[2:]:
        try:
            res = pack(t, out, n)
        except Exception as e:  # сеть или странная статья: идём дальше
            res = f'{t}: ошибка {e}'
        print(res)
        if res.startswith(f'{n:02d} '):
            n += 1
