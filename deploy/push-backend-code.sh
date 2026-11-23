#!/usr/bin/env bash
# Compila el backend y sube SOLO el código compilado (dist) al servidor, luego reinicia la API.
# No toca el .env ni instala paquetes. Uso:  bash deploy/push-backend-code.sh
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="${SSH_KEY:-ssh-key-2026-11-22.key}"; HOST="${SSH_HOST:-opc@129.146.251.187}"

( cd backend && rm -rf dist && npm run build >/dev/null )
# El inicio de sesión propio todavía no se publica: se excluye del paquete.
rm -rf backend/dist/modules/auth
tar -czf /tmp/api-code.tgz -C backend dist
echo "Subiendo código ($(du -h /tmp/api-code.tgz | cut -f1))..."
scp -i "$KEY" -o ConnectTimeout=20 /tmp/api-code.tgz "$HOST:/tmp/api-code.tgz"
ssh -i "$KEY" -o ConnectTimeout=20 "$HOST" '
  set -e
  sudo rm -rf /opt/sabero-academy/current/backend/dist.old
  sudo mv /opt/sabero-academy/current/backend/dist /opt/sabero-academy/current/backend/dist.old
  sudo tar -xzf /tmp/api-code.tgz -C /opt/sabero-academy/current/backend
  sudo chown -R sabero:sabero /opt/sabero-academy/current/backend/dist
  rm -f /tmp/api-code.tgz
  sudo systemctl restart sabero-academy-api && sleep 4
  curl -fsS http://127.0.0.1:3000/api/v1/health && echo
  curl -s -o /dev/null -w "cronograma (sin sesión, debe ser 401): %{http_code}\n" http://127.0.0.1:3000/api/v1/schedule
  sudo rm -rf /opt/sabero-academy/current/backend/dist.old
'
rm -f /tmp/api-code.tgz
echo "Listo."
