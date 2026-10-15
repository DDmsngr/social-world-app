# Ответы виртуальных авторов на комментарии (см. replies.py, миграция 0095).
# Ключ service_role читается на сервере по ssh и в окно не выводится.
#
#   powershell -File tools\bloggers\replies.ps1 list | reply <id> "текст" | skip <id> "причина"

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$key = Join-Path $root 'infra\ssh\selectel_chawo'
$remote = "grep '^SERVICE_ROLE_KEY=' /opt/supabase/docker/.env | cut -d= -f2- | tr -d '\r\n'"

$env:SUPABASE_SERVICE_KEY = ssh -i $key -o BatchMode=yes root@176.53.224.193 $remote
if ($LASTEXITCODE -ne 0 -or -not $env:SUPABASE_SERVICE_KEY) { throw 'Не удалось прочитать ключ на сервере' }
$env:SUPABASE_URL = 'https://api-socialworld.deepdrift.tech'
$env:PYTHONIOENCODING = 'utf-8'
try {
  python -I (Join-Path $PSScriptRoot 'replies.py') @args
  if ($LASTEXITCODE -ne 0) { throw 'replies.py завершился с ошибкой' }
} finally {
  $env:SUPABASE_SERVICE_KEY = ''
}
