"""Ответы виртуальных авторов на комментарии (миграция 0095).

    powershell -File tools\\bloggers\\replies.ps1 list
    powershell -File tools\\bloggers\\replies.ps1 reply <comment_id> "текст ответа"
    powershell -File tools\\bloggers\\replies.ps1 skip <comment_id> "причина"
    powershell -File tools\\bloggers\\replies.ps1 auto        # YandexGPT, когда будет ключ

list печатает очередь: кто автор, его характер, пост, вся ветка и комментарий,
на который ждут ответ. До релиза отвечает редакция (Claude) по этому выводу
раз в сутки, вместе с ночным разбором багов. auto делает то же самое через
YandexGPT по тем же правилам (RULES и prompt()), чтобы потом перенести его на
сервер без переделки: нужны YANDEX_API_KEY и YANDEX_FOLDER_ID.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
HERE = os.path.dirname(os.path.abspath(__file__))
PERSONAS = json.load(open(os.path.join(HERE, 'personas.json'), encoding='utf-8'))

# Порог на автора в одной ветке: дальше разговор ведут люди.
MAX_PER_THREAD = 3

RULES = """Правила ответа:
- Ты виртуальный автор ChaWo, тебя ведёт редакция. На прямой вопрос «ты бот?» честно отвечай, что ты виртуальный автор.
- Отвечай только по теме своего поста и того, что есть в посте и его источнике. Чего там нет, того не знаешь: так и скажи, не выдумывай факты, цифры, даты, цены и цитаты.
- Личного опыта у тебя нет: не пиши «я была», «я пробовал».
- Не обсуждай политику, медицину, деньги, юридические вопросы: вежливо уйди от темы одной фразой.
- Оскорбления, спам, провокации, реклама — не отвечай (действие skip).
- Пиши как живой человек в комментариях: 1–3 предложения, до 400 знаков, на «ты» или «вы» так же, как к тебе обратились. Без хэштегов, без ссылок, без эмодзи-гирлянд (одно эмодзи можно).
- Не начинай с «Спасибо за комментарий» и не повторяй вопрос.
- Если отвечать нечего (комментарий вроде «класс»), можно коротко поблагодарить по-человечески или пропустить."""


def call(method, path, data=None):
    req = urllib.request.Request(URL + path, method=method,
                                 data=None if data is None else json.dumps(data).encode())
    req.add_header('apikey', KEY)
    req.add_header('Authorization', 'Bearer ' + KEY)
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {path}: {e.code} {e.read().decode("utf-8", "replace")[:300]}')


def ids(values):
    return ','.join(sorted(set(values)))


def pending():
    """Очередь с контекстом: пост, ветка, автор."""
    queue = call('GET', '/rest/v1/author_reply_queue?status=eq.pending&order=created_at&limit=200')
    if not queue:
        return []
    posts = {p['id']: p for p in call('GET', f'/rest/v1/posts?select=id,body,created_at,author_id&id=in.({ids(q["post_id"] for q in queue)})')}
    comments = call('GET', f'/rest/v1/post_comments?select=id,parent_id,author_id,body,created_at,deleted_at,status'
                           f'&post_id=in.({ids(q["post_id"] for q in queue)})&order=created_at')
    people = ids([c['author_id'] for c in comments] + [q['author_id'] for q in queue])
    profiles = {p['id']: p for p in call('GET', f'/rest/v1/profiles?select=id,username,display_name&id=in.({people})')}
    out = []
    for q in queue:
        author = profiles.get(q['author_id'], {})
        chain = _thread_ids(comments, q['comment_id'])
        thread = [c for c in comments if c['id'] in chain]
        root = next((c['id'] for c in thread if c['parent_id'] is None), None)
        mine = sum(1 for c in _subtree(comments, root) if c['author_id'] == q['author_id'])
        out.append({
            'comment_id': q['comment_id'],
            'author': author.get('username'),
            'persona': PERSONAS.get(author.get('username') or '', {}),
            'post': posts.get(q['post_id'], {}).get('body', ''),
            'thread': [{
                'id': c['id'],
                'who': 'автор' if c['author_id'] == q['author_id'] else (profiles.get(c['author_id'], {}).get('display_name') or 'человек'),
                'text': '[удалён]' if c['deleted_at'] or c['status'] == 'blocked' else c['body'],
                'target': c['id'] == q['comment_id'],
            } for c in thread],
            'author_replies_in_thread': mine,
        })
    return out


def _thread_ids(comments, leaf):
    """Ветка от корня до комментария, плюс уже данные ответы на него."""
    by_id = {c['id']: c for c in comments}
    chain, cur = [], by_id.get(leaf)
    while cur:
        chain.append(cur['id'])
        cur = by_id.get(cur['parent_id'])
    chain += [c['id'] for c in comments if c['parent_id'] == leaf]
    return set(chain)


def _subtree(comments, root):
    """Вся ветка от корневого комментария: для лимита ответов автора."""
    found, grew = {root}, True
    while grew:
        grew = False
        for c in comments:
            if c['parent_id'] in found and c['id'] not in found:
                found.add(c['id'])
                grew = True
    return [c for c in comments if c['id'] in found]


def prompt(item):
    p = item['persona']
    thread = '\n'.join(f'{"→ " if t["target"] else ""}{t["who"]}: {t["text"]}' for t in item['thread'])
    return (f'Ты {p.get("name")}, виртуальный автор соцсети ChaWo. Тема: {p.get("topic")}. Характер: {p.get("voice")}.\n\n'
            f'{RULES}\n\nТвой пост:\n{item["post"]}\n\nВетка комментариев (стрелкой отмечен тот, на который отвечаешь):\n{thread}\n\n'
            'Верни JSON: {"action": "reply", "text": "..."} или {"action": "skip", "reason": "..."}')


def check(text):
    text = text.strip()
    if not 2 <= len(text) <= 600:
        sys.exit(f'длина ответа {len(text)}, нужно 2–600')
    if re.search(r'https?://|#\w', text):
        sys.exit('в ответе ссылка или хэштег')
    return text


def reply(comment_id, text, by='editor'):
    new_id = call('POST', '/rest/v1/rpc/author_reply_post', {'p_comment': comment_id, 'p_body': check(text), 'p_by': by})
    print('ответ', new_id or 'не нужен: комментарий удалён')


def skip(comment_id, note, by='editor'):
    call('POST', '/rest/v1/rpc/author_reply_skip', {'p_comment': comment_id, 'p_note': note, 'p_by': by})
    print('пропущен')


def yandex(text):
    key, folder = os.environ.get('YANDEX_API_KEY'), os.environ.get('YANDEX_FOLDER_ID')
    if not key or not folder:
        sys.exit('YandexGPT не подключён: нужны YANDEX_API_KEY и YANDEX_FOLDER_ID')
    body = {
        'modelUri': f'gpt://{folder}/yandexgpt/latest',
        'completionOptions': {'stream': False, 'temperature': 0.5, 'maxTokens': 400},
        'messages': [{'role': 'user', 'text': text}],
    }
    req = urllib.request.Request('https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
                                 data=json.dumps(body).encode(), method='POST')
    req.add_header('Authorization', 'Api-Key ' + key)
    req.add_header('x-folder-id', folder)
    req.add_header('Content-Type', 'application/json')
    with urllib.request.urlopen(req, timeout=60) as r:
        answer = json.loads(r.read())['result']['alternatives'][0]['message']['text']
    found = re.search(r'\{.*\}', answer, re.S)
    return json.loads(found.group(0)) if found else {'action': 'skip', 'reason': 'модель ответила не JSON'}


def auto():
    for item in pending():
        if item['author_replies_in_thread'] >= MAX_PER_THREAD:
            skip(item['comment_id'], 'лимит ответов в ветке', 'yandexgpt')
            continue
        decision = yandex(prompt(item))
        if decision.get('action') == 'reply' and decision.get('text'):
            reply(item['comment_id'], decision['text'], 'yandexgpt')
        else:
            skip(item['comment_id'], decision.get('reason') or 'модель пропустила', 'yandexgpt')


def show():
    items = pending()
    print(f'в очереди {len(items)}\n')
    for item in items:
        p = item['persona']
        print(f'=== {item["comment_id"]}  {p.get("name")} (@{item["author"]}), ответов автора в ветке: {item["author_replies_in_thread"]}')
        print('пост:', item['post'][:700].replace('\n', ' '))
        for t in item['thread']:
            print(('  → ' if t['target'] else '    ') + f'{t["who"]}: {t["text"]}')
        print()
    if items:
        print(RULES)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'list'
    if cmd == 'list':
        show()
    elif cmd == 'reply' and len(sys.argv) == 4:
        reply(sys.argv[2], sys.argv[3])
    elif cmd == 'skip' and len(sys.argv) == 4:
        skip(sys.argv[2], sys.argv[3])
    elif cmd == 'auto':
        auto()
    else:
        sys.exit(__doc__)
