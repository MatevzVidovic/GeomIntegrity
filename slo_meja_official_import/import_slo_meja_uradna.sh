#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHP_PATH="${SHP_PATH:-$SCRIPT_DIR/DRZAVNA_MEJA/EDM-mejna_crta.shp}"

RAW_SCHEMA="${RAW_SCHEMA:-public}"
RAW_TABLE="${RAW_TABLE:-slo_meja_uradna_raw}"
TARGET_SCHEMA="${TARGET_SCHEMA:-public}"
TARGET_TABLE="${TARGET_TABLE:-slo_meja_uradna}"

: "${PGHOST:?Set PGHOST}"
: "${PGDATABASE:?Set PGDATABASE}"
: "${PGUSER:?Set PGUSER}"

if [[ ! -f "$SHP_PATH" ]]; then
  echo "Missing shapefile: $SHP_PATH" >&2
  exit 1
fi

# echo "[1/2] Loading raw official border lines into ${RAW_SCHEMA}.${RAW_TABLE}"
# shp2pgsql -d -s 3794 -I -W UTF-8 "$SHP_PATH" "${RAW_SCHEMA}.${RAW_TABLE}" \
#   | psql -v ON_ERROR_STOP=1

echo "[1/2] Loading raw official border lines into ${RAW_SCHEMA}.${RAW_TABLE}"
shp2pgsql -c -s 3794 -I -W UTF-8 "$SHP_PATH" "${RAW_SCHEMA}.${RAW_TABLE}" \
  | psql -v ON_ERROR_STOP=1

echo "[2/2] Building official Slovenia boundary multipolygon in ${TARGET_SCHEMA}.${TARGET_TABLE}"
psql -v ON_ERROR_STOP=1 \
  -v raw_schema="$RAW_SCHEMA" \
  -v raw_table="$RAW_TABLE" \
  -v target_schema="$TARGET_SCHEMA" \
  -v target_table="$TARGET_TABLE" \
  -f "$SCRIPT_DIR/sql/01_build_slo_meja_uradna.sql"

echo "Import complete."
