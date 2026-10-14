"""Расшифровка голосового или звука из видео для Помощника: печатает текст.

    python -I transcribe.py файл.m4a

faster-whisper на процессоре, модель small, русский. Модели — на диске D:
(HF_HOME), диск C: не трогаем. Первый запуск скачивает модель (~0,5 ГБ).
"""
import os
import sys

os.environ.setdefault('HF_HOME', r'D:\hf-cache')

from faster_whisper import WhisperModel  # noqa: E402


def main(path):
    model = WhisperModel('small', device='cpu', compute_type='int8',
                         download_root=os.path.join(os.environ['HF_HOME'], 'whisper'))
    segments, _ = model.transcribe(path, language='ru')
    text = ' '.join(s.text.strip() for s in segments).strip()
    sys.stdout.reconfigure(encoding='utf-8')
    print(text or '(речи не слышно)')


if __name__ == '__main__':
    main(sys.argv[1])
