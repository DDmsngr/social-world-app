param(
  [Parameter(Mandatory = $true)][ValidateSet('list', 'ack', 'reply')][string]$Action,
  [string]$Text,
  [string]$OutDir = 'D:\temp\assistant'
)
# Почта «Помощника»: читаем сообщения владельца из чата ChaWo, скачиваем
# скриншоты, отмечаем забранное и отвечаем.
#   list  — новые сообщения (скриншоты скачиваются в $OutDir)
#   ack   — пометить все новые как забранные
#   reply — ответить в чат текстом: -Text "..."
#
# С 08.10.2026 база живёт на собственном сервере в Яндекс Облаке (раньше —
# Supabase Cloud, через Management API). Ходим на сервер по ssh (алиас
# socialworld): SQL уходит файлом, ответ возвращается в base64 — иначе
# кириллицу ломает кодировка консоли. Скриншоты лежат в томе хранилища на
# сервере, копируем их scp. Ключи не нужны и наружу не печатаются.

$ErrorActionPreference = 'Stop'
$server = 'socialworld'
$bucketDir = '/opt/supabase/docker/volumes/storage/stub/stub/assistant'

function Remote([string]$script) {
  $local = Join-Path $env:TEMP 'inbox_run.sh'
  [IO.File]::WriteAllText($local, $script.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
  scp -q $local "${server}:/tmp/inbox_run.sh"
  if ($LASTEXITCODE -ne 0) { throw 'scp не удался' }
  $out = ssh $server 'sudo -n sh /tmp/inbox_run.sh | base64 -w0'
  if ($LASTEXITCODE -ne 0) { throw 'ssh не удался' }
  $joined = ($out -join '')
  if (-not $joined) { return '' }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($joined))
}

function Psql([string]$sql) {
  # Запрос кладём в файл на сервере, чтобы не бороться с кавычками.
  $sqlLocal = Join-Path $env:TEMP 'inbox_q.sql'
  [IO.File]::WriteAllText($sqlLocal, $sql.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
  scp -q $sqlLocal "${server}:/tmp/inbox_q.sql"
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
  where m.from_user and m.handled_at is null
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
        scp -q "${server}:$tmp" $file
        if ($LASTEXITCODE -ne 0) { throw "Не скачался скриншот $($r.attachment_path)" }
        Remote "shred -u '$tmp' 2>/dev/null || true" | Out-Null
        "[скриншот] $file"
      }
    }
  }
  'ack' {
    Psql "update assistant_messages set handled_at = now() where from_user and handled_at is null;" | Out-Null
    'Отмечено.'
  }
  'reply' {
    if (-not $Text) { throw 'Нужен -Text' }
    $safe = $Text.Replace("'", "''")
    Psql "insert into assistant_messages (from_user, body) values (false, '$safe');" | Out-Null
    'Ответ отправлен.'
  }
}
