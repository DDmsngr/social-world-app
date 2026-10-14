"""Расшифровка голосового или звука из видео для Помощника: печатает текст.

    python -I transcribe.py файл.m4a

faster-whisper на процессоре, модель medium, русский. Модели — на диске D:
(HF_HOME), диск C: не трогаем. Первый запуск скачивает модель (~1,5 ГБ).
"""
import os
import sys

os.environ.setdefault('HF_HOME', r'D:\hf-cache')

from faster_whisper import WhisperModel  # noqa: E402


def main(path):
    model = WhisperModel('medium', device='cpu', compute_type='int8',
                         download_root=os.path.join(os.environ['HF_HOME'], 'whisper'))
    # Подсказка со словами проекта: имена и термины иначе слышатся как попало.
    segments, _ = model.transcribe(
        path, language='ru', beam_size=5,
        initial_prompt='ChaWo, чат, блик, Помощник, стикеры, канал, лента, Артур, Левон, Белов, Соня, Марк, Илья, Тихон, Вера, Артём, тестировщик, сборка.',
    )
    text = ' '.join(s.text.strip() for s in segments).strip()
    sys.stdout.reconfigure(encoding='utf-8')
    print(text or '(речи не слышно)')


if __name__ == '__main__':
    main(sys.argv[1])
