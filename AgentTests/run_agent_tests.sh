#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required but not found in PATH" >&2
  exit 1
fi

eval "$(PYTHONPATH="$ROOT_DIR" python3 - <<'PY'
import shlex
from db_config.config import DATABASE_CONFIG as c

print("export PGHOST={}".format(shlex.quote(str(c["host"]))))
print("export PGPORT={}".format(shlex.quote(str(c["port"]))))
print("export PGDATABASE={}".format(shlex.quote(str(c["database"]))))
print("export PGUSER={}".format(shlex.quote(str(c["user"]))))
print("export PGPASSWORD={}".format(shlex.quote(str(c["password"]))))
PY
)"

SQL_SCRIPTS=(
  "$ROOT_DIR/AgentTests/01_full_validations.sql"
  "$ROOT_DIR/AgentTests/02_topology_trigger_incremental.sql"
  "$ROOT_DIR/AgentTests/03_hierarchy_trigger_incremental.sql"
)

run_psql_with_retry() {
  local script_path="$1"
  local attempt=1
  local max_attempts=3

  while true; do
    if psql -X -v ON_ERROR_STOP=1 -f "$script_path"; then
      return 0
    fi

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "Failed $(basename "$script_path") after $attempt attempts" >&2
      return 1
    fi

    echo "Retrying $(basename "$script_path") after transient failure ($attempt/$max_attempts)..." >&2
    attempt=$((attempt + 1))
    sleep 2
  done
}

for script in "${SQL_SCRIPTS[@]}"; do
  echo "Running $(basename "$script")"
  run_psql_with_retry "$script"
done

echo "All AgentTests scripts passed."
