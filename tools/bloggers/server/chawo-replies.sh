#!/bin/bash
# Автоответы виртуальных авторов на комментарии (cron, каждые 10 минут).
# Ставится в /usr/local/bin; replies.py и personas.json лежат в /opt/chawo-replies.
set -euo pipefail
exec 9>/run/lock/chawo-replies.lock
flock -n 9 || exit 0

DIR=/opt/chawo-replies
export SUPABASE_URL=https://api-socialworld.deepdrift.tech
export SUPABASE_SERVICE_KEY="$(grep '^SERVICE_ROLE_KEY=' /opt/supabase/docker/.env | cut -d= -f2- | tr -d '\r\n')"
export ANTHROPIC_API_KEY="$(tr -d '\r\n' < "$DIR/anthropic.key")"
# Прокси к Anthropic (из РФ он закрыт): строки ANTHROPIC_PROXY_URL= и ANTHROPIC_PROXY_TOKEN=.
if [ -f "$DIR/proxy.env" ]; then set -a; . "$DIR/proxy.env"; set +a; fi
export REPLIES_LLM=haiku
export PYTHONIOENCODING=utf-8

# Не больше 5 ответов за запуск: страховка от шторма комментариев.
echo "== $(date -Is)"
python3 -I "$DIR/replies.py" auto 5
