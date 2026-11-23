#!/usr/bin/env bash
# Crea (o actualiza) la base de datos en PostgreSQL puro.
# Uso:  DATABASE_URL=postgresql://postgres@127.0.0.1:5544/academy bash db/apply.sh
# El rol de DATABASE_URL debe poder crear roles, esquemas y extensiones (por ejemplo "postgres").
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DATABASE_URL:?Indica DATABASE_URL}"
PSQL="${PSQL:-psql}"
# Los archivos SQL están en UTF-8 (tildes y ñ): sin esto, Windows los guardaría mal codificados.
export PGCLIENTENCODING=UTF8

run() { echo "→ $1"; "$PSQL" "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$1" >/dev/null; }

run db/platform.sql
for f in supabase/migrations/*.sql; do run "$f"; done
# Cambios propios de la base independiente (después de las migraciones históricas).
for f in db/migrations/*.sql; do [ -e "$f" ] && run "$f"; done
echo "Base de datos lista."
