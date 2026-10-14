param(
  [Parameter(Mandatory = $true)][ValidateSet('list', 'ack', 'reply')][string]$Action,
  [string]$Text,
  [string]$File,
  [string]$OutDir = 'D:\temp\assistant'
)
# Почта «Помощника»: читаем сообщения владельца из чата ChaWo, скачиваем
# скриншоты, отмечаем забранное и отвечаем.
#   list  — новые сообщения (скриншоты скачиваются в $OutDir)
#   ack   — пометить все новые как забранные
#   reply — ответить в чат текстом: -Text "..."; с файлом (картинка, видео,
#           pdf до 25 МБ): -File путь [-Text подпись]
#
# С 08.10.2026 база живёт на собственном сервере в Яндекс Облаке (раньше —
# Supabase Cloud, через Management API). Ходим на сервер по ssh (алиас
# socialworld): SQL уходит файлом, ответ возвращается в base64 — иначе
# кириллицу ломает кодировка консоли. Скриншоты лежат в томе хранилища на
# сервере, копируем их scp. Ключи не нужны и наружу не печатаются.

$ErrorActionPreference = 'Stop'
# 12.10.2026: переезд из Яндекс Облака (авария) в Selectel, Москва; заходим
# напрямую по ключу из infra/ssh (в git его нет).
$server = 'root@176.53.224.193'
$sshOpts = @('-i', (Join-Path $PSScriptRoot '..\..\infra\ssh\selectel_chawo'), '-o', 'BatchMode=yes')
$bucketDir = '/opt/supabase/docker/volumes/storage/stub/stub/assistant'

function Remote([string]$script) {
  $local = Join-Path $env:TEMP 'inbox_run.sh'
  [IO.File]::WriteAllText($local, $script.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
  scp -q @sshOpts $local "${server}:/tmp/inbox_run.sh"
  if ($LASTEXITCODE -ne 0) { throw 'scp не удался' }
  $out = ssh @sshOpts $server 'sudo -n sh /tmp/inbox_run.sh | base64 -w0'
  if ($LASTEXITCODE -ne 0) { throw 'ssh не удался' }
  $joined = ($out -join '')
  if (-not $joined) { return '' }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($joined))
}

function Psql([string]$sql) {
  # Запрос кладём в файл на сервере, чтобы не бороться с кавычками.
  $sqlLocal = Join-Path $env:TEMP 'inbox_q.sql'
  [IO.File]::WriteAllText($sqlLocal, $sql.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
  scp -q @sshOpts $sqlLocal "${server}:/tmp/inbox_q.sql"
  if ($LASTEXITCODE -ne 0) { throw 'scp не удался' }
  Remote "docker cp /tmp/inbox_q.sql supabase-db:/tmp/inbox_q.sql`ndocker exec supabase-db psql -U postgres -d postgres -At -v ON_ERROR_STOP=1 -f /tmp/inbox_q.sql"
}

switch ($Action) {
  'list' {
    $json = Psql @"
select coalesce(json_agg(t), '[]'::json) from (
  select m.id, m.body, m.attachment_path, m.created_at, o.version
  from assistant_messages m
  left join storage.objects o on o.bucket_id = 'assistant' and o.name = m.attachment_path
  where m.from_user and m.handled_at is null and m.channel = 'assistant'
  order by m.created_at
) t;
"@
    $rows = $json.Trim() | ConvertFrom-Json
    if (-not $rows -or @($rows).Count -eq 0) { 'Новых сообщений нет.'; return }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    foreach ($r in @($rows)) {
      "--- $($r.created_at)"
      if ($r.body) { $r.body }
      if ($r.attachment_path -and $r.version) {
        $file = Join-Path $OutDir ($r.attachment_path -replace '/', '_')
        $tmp = "/tmp/inbox_$($r.id).bin"
        Remote "cp '$bucketDir/$($r.attachment_path)/$($r.version)' '$tmp' && chmod 644 '$tmp'" | Out-Null
        scp -q @sshOpts "${server}:$tmp" $file
        if ($LASTEXITCODE -ne 0) { throw "Не скачался скриншот $($r.attachment_path)" }
        Remote "shred -u '$tmp' 2>/dev/null || true" | Out-Null
        if ($file -match '\.(m4a|aac|mp3|ogg|wav|opus|mp4|mov|3gp|webm|mkv)$') {
          # Голосовое или видео: речь расшифровывает faster-whisper здесь же.
          "[файл] $file"
          $env:HF_HOME = 'D:\hf-cache'
          # python печатает UTF-8, а консоль PowerShell по умолчанию читает cp866.
          $oldEncoding = [Console]::OutputEncoding
          [Console]::OutputEncoding = [Text.Encoding]::UTF8
          $said = & python -I (Join-Path $PSScriptRoot 'transcribe.py') $file 2>$null
          [Console]::OutputEncoding = $oldEncoding
          if ($LASTEXITCODE -eq 0 -and $said) { "[расшифровка] $($said -join ' ')" } else { '[расшифровка не удалась]' }
        } else {
          "[скриншот] $file"
        }
      }
    }
  }
  'ack' {
    Psql "update assistant_messages set handled_at = now() where from_user and handled_at is null and channel = 'assistant';" | Out-Null
    'Отмечено.'
  }
  'reply' {
    if ($File) {
      if (-not (Test-Path -LiteralPath $File)) { throw "Нет файла $File" }
      $remote = "grep '^SERVICE_ROLE_KEY=' /opt/supabase/docker/.env | cut -d= -f2- | tr -d '
'"
      $env:SUPABASE_SERVICE_KEY = ssh @sshOpts $server $remote
      if ($LASTEXITCODE -ne 0 -or -not $env:SUPABASE_SERVICE_KEY) { throw 'Не удалось прочитать ключ на сервере' }
      $env:SUPABASE_URL = 'https://api-socialworld.deepdrift.tech'
      $env:PYTHONIOENCODING = 'utf-8'
      try {
        python -I (Join-Path $PSScriptRoot 'send_file.py') $File $Text
        if ($LASTEXITCODE -ne 0) { throw 'Файл не отправлен' }
      } finally {
        $env:SUPABASE_SERVICE_KEY = ''
      }
      return
    }
    if (-not $Text) { throw 'Нужен -Text' }
    $safe = $Text.Replace("'", "''")
    Psql "insert into assistant_messages (from_user, body) values (false, '$safe');" | Out-Null
    'Ответ отправлен.'
  }
}
