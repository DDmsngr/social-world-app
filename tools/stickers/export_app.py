"""Кладёт стикеры в ассеты приложения: assets/stickers/<пак>/<ключ>.webp и
assets/stickers/manifest.json. Id стикера = '<пак>.<ключ>' — он уходит в
сообщения и меняться не должен.
Запуск: python3 -I export_app.py <папка с нарезкой> <assets/stickers>
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tags import EMOJI, FAMILIES, TAGS  # noqa: E402

PACKS = [  # папка нарезки, id пака в приложении, название
    ('pack1_basic', 'basic', 'Основные'),
    ('pack2_more', 'more', 'Ещё эмоции'),
    ('pack3_city', 'city', 'Город и настроение'),
    ('pack4_chao', 'chao', 'Чао'),
]


def main(src, dst):
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    packs = []
    for folder, pid, title in PACKS:
        files = {f.split('_', 1)[1].rsplit('.', 1)[0]: f for f in os.listdir(os.path.join(src, folder))}
        os.makedirs(os.path.join(dst, pid))
        stickers = []
        for key, (name, fams, extra) in TAGS[folder].items():
            shutil.copy(os.path.join(src, folder, files[key]), os.path.join(dst, pid, key + '.webp'))
            stickers.append({
                'id': f'{pid}.{key}',
                'emoji': EMOJI[folder][key],
                'title': name,
                'synonyms': extra,
                'emotions': fams,
            })
        assert len(stickers) == 35 and set(files) == set(TAGS[folder]) == set(EMOJI[folder]), folder
        packs.append({'id': pid, 'title': title, 'stickers': stickers})
    data = {'version': 1, 'families': FAMILIES, 'packs': packs}
    with open(os.path.join(dst, 'manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(',', ':'))
    print('ok', sum(len(p['stickers']) for p in packs))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
