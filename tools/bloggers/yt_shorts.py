"""Search YouTube Shorts by topic via yt-dlp, filter by duration, sort by views.

Usage:
    python yt_shorts.py "Сочи" --results 20 --max-seconds 90 --limit 10

Requires yt-dlp on PATH. Does not download video/audio, only metadata
(`--dump-json`, `--skip-download` implicit in search mode).
"""
import argparse
import json
import subprocess
import sys


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("topic", help="search query, e.g. 'Сочи' or 'Сочи море'")
    parser.add_argument("--results", type=int, default=20, help="how many search results to fetch before filtering")
    parser.add_argument("--max-seconds", type=int, default=90, help="drop videos longer than this (Shorts cutoff)")
    parser.add_argument("--limit", type=int, default=10, help="how many rows to print, after sorting by views")
    args = parser.parse_args()

    proc = subprocess.run(
        ["yt-dlp", "--dump-json", f"ytsearch{args.results}:{args.topic}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if proc.returncode != 0:
        print(f"yt-dlp failed (exit {proc.returncode}):", file=sys.stderr)
        print(proc.stderr[-2000:], file=sys.stderr)
        sys.exit(1)

    rows = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        duration = d.get("duration") or 0
        if duration > args.max_seconds:
            continue
        rows.append(d)

    rows.sort(key=lambda d: d.get("view_count") or 0, reverse=True)

    if not rows:
        print(f"Ничего короче {args.max_seconds}с не нашлось среди {args.results} результатов по «{args.topic}».")
        return

    for d in rows[: args.limit]:
        views = d.get("view_count") or 0
        duration = d.get("duration") or 0
        uploader = str(d.get("uploader") or "?")[:28]
        title = (d.get("title") or "")[:60]
        print(f"{views:>8} просм | {duration:>4.0f}с | {uploader:<28} | {title}")
        print(f"  https://youtu.be/{d.get('id')}")


if __name__ == "__main__":
    main()
