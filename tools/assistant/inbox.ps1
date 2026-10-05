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
# Токен Management API берётся из файла, наружу не печатается.

$ErrorActionPreference = 'Stop'
$ref = 'veofltvuenisdzbqvwkr'
$token = (Get-Content 'D:\Temp\supabase-token.txt' -Raw).Trim()
$h = @{ Authorization = "Bearer $token" }

function Sql([string]$query) {
  $body = @{ query = $query } | ConvertTo-Json
  $bytes = [Text.Encoding]::UTF8.GetBytes($body)
  Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$ref/database/query" `
    -Headers $h -ContentType 'application/json; charset=utf-8' -Body $bytes
}

switch ($Action) {
  'list' {
    $rows = Sql "select id, body, attachment_path, created_at from assistant_messages where from_user and handled_at is null order by created_at"
    if (-not $rows -or $rows.Count -eq 0) { 'Новых сообщений нет.'; return }
    $keys = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/api-keys" -Headers $h
    $service = ($keys | Where-Object { $_.name -eq 'service_role' }).api_key
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    foreach ($r in $rows) {
      "--- $($r.created_at)"
      if ($r.body) { $r.body }
      if ($r.attachment_path) {
        $file = Join-Path $OutDir ($r.attachment_path -replace '/', '_')
        Invoke-WebRequest -Uri "https://api-socialworld.deepdrift.tech/storage/v1/object/assistant/$($r.attachment_path)" `
          -Headers @{ Authorization = "Bearer $service"; apikey = $service } -OutFile $file
        "[скриншот] $file"
      }
    }
  }
  'ack' {
    Sql "update assistant_messages set handled_at = now() where from_user and handled_at is null" | Out-Null
    'Отмечено.'
  }
  'reply' {
    if (-not $Text) { throw 'Нужен -Text' }
    $safe = $Text.Replace("'", "''")
    Sql "insert into assistant_messages (from_user, body) values (false, '$safe')" | Out-Null
    'Ответ отправлен.'
  }
}
