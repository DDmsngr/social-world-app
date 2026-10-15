#!/bin/sh
# Расшифровка бэкапа ChaWo на машине владельца (где лежит закрытый ключ).
#   backup-decrypt.sh закрытый_ключ.pem файл.enc выход
# Рядом с файлом должен лежать файл.enc.key (его кладёт бэкап).
# Дамп после этого открывается так: pg_restore --list выход
# На Windows (git bash) перед запуском: export TMPDIR=D:/temp
set -e
key=$1; in=$2; out=$3
k=$(mktemp)
openssl pkeyutl -decrypt -inkey "$key" -pkeyopt rsa_padding_mode:oaep -in "$in.key" -out "$k"
openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$k" < "$in" > "$out"
rm -f "$k"
