# Публикует паки стикеров в магазин ChaWo (см. publish_packs.py).
# Ключ service_role читается на сервере по ssh и в окно не выводится.
#
#   powershell -File tools\stickers\publish.ps1            # все паки
#   powershell -File tools\stickers\publish.ps1 alexa      # один пак

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$key = Join-Path $root 'infra\ssh\selectel_chawo'
$remote = "grep '^SERVICE_ROLE_KEY=' /opt/supabase/docker/.env | cut -d= -f2- | tr -d '\r\n'"

$env:SUPABASE_SERVICE_KEY = ssh -i $key -o BatchMode=yes root@176.53.224.193 $remote
if ($LASTEXITCODE -ne 0 -or -not $env:SUPABASE_SERVICE_KEY) { throw 'Не удалось прочитать ключ на сервере' }
$env:SUPABASE_URL = 'https://api-socialworld.deepdrift.tech'
$env:PYTHONIOENCODING = 'utf-8'
try {
  python -I (Join-Path $PSScriptRoot 'publish_packs.py') @args
  if ($LASTEXITCODE -ne 0) { throw 'Публикация не прошла' }
} finally {
  $env:SUPABASE_SERVICE_KEY = ''
}
