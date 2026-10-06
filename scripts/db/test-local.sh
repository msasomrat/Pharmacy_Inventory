#!/usr/bin/env bash
# Fast local database test runner WITHOUT Docker.
# Creates a throwaway PostgreSQL cluster, loads a Supabase shim, applies every migration in order,
# then runs all pgTAP tests. Requires PostgreSQL 15+ server binaries and pgTAP (pg_prove).
# The authoritative run is `pnpm test:db` (real Supabase stack), which CI executes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PG_BIN="${PG_BIN:-$(dirname "$(command -v pg_ctl 2>/dev/null || ls -d /usr/lib/postgresql/*/bin/pg_ctl | sort -V | tail -1)")}"
WORK="$(mktemp -d)"
PORT="${PORT:-54329}"
RUN=()
if [ "$(id -u)" = "0" ]; then
  chown postgres "$WORK"
  RUN=(runuser -u postgres --)
fi

cleanup() {
  "${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${RUN[@]}" "$PG_BIN/initdb" -D "$WORK/data" -U postgres -A trust -E UTF8 --locale=C.UTF-8 >/dev/null
"${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses='' -c timezone=UTC" -w start >/dev/null

PSQL=("${RUN[@]}" env PGOPTIONS="-c client_min_messages=warning" psql -X -q -v ON_ERROR_STOP=1 -h "$WORK" -p "$PORT" -U postgres -d postgres)

"${PSQL[@]}" -f "$ROOT/scripts/db/supabase-shim.sql"

shopt -s nullglob
for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "migrate  $(basename "$migration")"
  "${PSQL[@]}" -f "$migration"
done
if [ -f "$ROOT/supabase/seed.sql" ] && [ "${SEED:-0}" = "1" ]; then
  echo "seed     supabase/seed.sql"
  "${PSQL[@]}" -f "$ROOT/supabase/seed.sql"
fi

tests=("$ROOT"/supabase/tests/database/*.sql)
if [ "${#tests[@]}" -eq 0 ]; then
  echo "No pgTAP tests found."
  exit 0
fi
# Copy tests somewhere the postgres user can read them.
mkdir -p "$WORK/tests" && cp "${tests[@]}" "$WORK/tests/" && chmod -R a+r "$WORK/tests"
"${RUN[@]}" pg_prove -h "$WORK" -p "$PORT" -U postgres -d postgres --ext .sql ${VERBOSE:+-v} "$WORK"/tests/*.sql
