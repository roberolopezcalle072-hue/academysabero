#!/usr/bin/env bash
# Sube backend/.env.production al servidor de Oracle y reinicia el backend.
# Uso (desde la carpeta del proyecto):  bash deploy/push-backend-env.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="backend/.env.production"
KEY="ssh-key-2026-11-22.key"
HOST="opc@129.146.251.187"

# --- Validaciones antes de subir nada ---
get() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2-; }
PROVIDER="$(get PAYMENT_PROVIDER)"; PK="$(get CULQI_PUBLIC_KEY)"; SK="$(get CULQI_SECRET_KEY)"; SECRET="$(get PAYMENT_INTERNAL_SECRET)"

[ -n "$(get SUPABASE_PUBLISHABLE_KEY)" ] && ! get SUPABASE_PUBLISHABLE_KEY | grep -q PEGAR || { echo "Falta SUPABASE_PUBLISHABLE_KEY en $ENV_FILE"; exit 1; }
[ ${#SECRET} -ge 32 ] || { echo "Falta PAYMENT_INTERNAL_SECRET en $ENV_FILE"; exit 1; }
if [ "$PROVIDER" = "culqi" ]; then
  [[ "$PK" =~ ^pk_(test|live)_[A-Za-z0-9]+$ ]] || { echo "CULQI_PUBLIC_KEY no es válida (debe empezar con pk_test_ o pk_live_). ¿Pegaste tu llave?"; exit 1; }
  [[ "$SK" =~ ^sk_(test|live)_[A-Za-z0-9]+$ ]] || { echo "CULQI_SECRET_KEY no es válida (debe empezar con sk_test_ o sk_live_). ¿Pegaste tu llave?"; exit 1; }
  [ "${PK:3:4}" = "${SK:3:4}" ] || { echo "Las dos llaves deben ser del mismo tipo: ambas de prueba (test) o ambas de producción (live)."; exit 1; }
  MODE="${PK:3:4}"
else
  MODE="sin pasarela"
fi

echo "Subiendo configuración al servidor (modo de pagos: $MODE)..."
scp -i "$KEY" -o ConnectTimeout=20 "$ENV_FILE" "$HOST:/tmp/backend.env"
ssh -i "$KEY" -o ConnectTimeout=20 "$HOST" '
  sudo install -m 0640 -o root -g sabero /tmp/backend.env /etc/sabero-academy/backend.env &&
  rm -f /tmp/backend.env &&
  sudo systemctl restart sabero-academy-api && sleep 3 &&
  curl -s http://127.0.0.1:3000/api/v1/health && echo &&
  echo -n "Pagos: " && curl -s http://127.0.0.1:3000/api/v1/payments/config && echo
'
echo "Listo. Comprueba también: https://aca.saberoconsulting.com/api/v1/payments/config"
