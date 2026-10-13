# Кладёт ключ service_role ЭТОГО сервера (Selectel) в секрет GitHub CHAWO_SERVICE_KEY.
# Ключ читается на сервере и сразу уходит в gh, на экран и в чат он не попадает.
#
# Запуск (один раз, и после любой смены ключей сервера):
#   powershell -File tools\ops\set-chawo-service-key.ps1
#
# Нужны: ключ ssh infra\ssh\selectel_chawo и gh, вошедший под владельцем репозитория.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$key = Join-Path $root 'infra\ssh\selectel_chawo'
$remote = "grep '^SERVICE_ROLE_KEY=' /opt/supabase/docker/.env | cut -d= -f2- | tr -d '\r\n'"

$value = ssh -i $key -o BatchMode=yes root@176.53.224.193 $remote
if ($LASTEXITCODE -ne 0 -or -not $value -or $value.Length -lt 40) { throw 'Не удалось прочитать ключ на сервере' }

$value | gh secret set CHAWO_SERVICE_KEY -R DDmsngr/social-world-app
if ($LASTEXITCODE -ne 0) { throw 'gh не принял секрет' }
Write-Host 'Готово: секрет CHAWO_SERVICE_KEY обновлён (длина ключа' $value.Length ').'
