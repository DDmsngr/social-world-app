#!/bin/sh
# Ночной бэкап: локальный дамп (7 дней) + выгрузка в S3 Selectel (бакет chawo-backups).
# С 15.10.2026 в S3 уходит ТОЛЬКО зашифрованное: дамп и конфиги шифруются открытым
# ключом (/root/.chawo-backup-pub.pem), закрытый ключ лежит у владельца и на
# сервере его нет. Файлы Storage шифрует rclone crypt (remote selcrypt).
# Расшифровка: tools/ops/backup-decrypt.sh.
set -e
d=/var/backups/chawo
pub=/root/.chawo-backup-pub.pem
stamp=$(date +%Y%m%d-%H%M)

# seal вход выход: AES-256 со случайным ключом, ключ — RSA-OAEP открытым ключом.
seal() {
  k=$(mktemp)
  head -c 48 /dev/urandom | base64 -w0 > "$k"
  openssl enc -aes-256-cbc -pbkdf2 -salt -pass "file:$k" < "$1" > "$2"
  openssl pkeyutl -encrypt -pubin -inkey "$pub" -pkeyopt rsa_padding_mode:oaep -in "$k" -out "$2.key"
  rm -f "$k"
}

f=$d/db-$stamp.dump
docker exec supabase-db pg_dump -U postgres -Fc postgres > "$f"
seal "$f" "$f.enc"
find $d -name 'db-*' -mtime +7 -delete

# Конфиги и ключи стека (.env, compose, Caddyfile, coturn, rclone.conf с ключами S3).
c=$d/config-$stamp.tar.gz
tar -czf "$c" -C /opt/supabase docker/.env docker/docker-compose.yml docker/docker-compose.caddy.yml \
  docker/docker-compose.chawo.yml docker/volumes/proxy/caddy/Caddyfile docker/volumes/functions \
  /etc/turnserver.conf /root/.config/rclone/rclone.conf 2>/dev/null || true
seal "$c" "$c.enc"
rm -f "$c"
find $d -name 'config-*' -mtime +7 -delete

# Off-site: дампы и конфиги 30 дней; файлы Storage только дополняем (шифруются).
rclone copy "$f.enc" sel:chawo-backups/db-enc/ --s3-no-check-bucket
rclone copy "$f.enc.key" sel:chawo-backups/db-enc/ --s3-no-check-bucket
rclone copy "$c.enc" sel:chawo-backups/config-enc/ --s3-no-check-bucket
rclone copy "$c.enc.key" sel:chawo-backups/config-enc/ --s3-no-check-bucket
rclone delete sel:chawo-backups/db-enc --min-age 30d --s3-no-check-bucket
rclone delete sel:chawo-backups/config-enc --min-age 30d --s3-no-check-bucket
rclone copy /opt/supabase/docker/volumes/storage selcrypt: --transfers 4 --quiet
echo "$(date -Is) ok $stamp (enc)" >> /var/log/chawo-backup.log
