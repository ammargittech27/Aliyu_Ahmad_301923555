#!/usr/bin/env bash
# portfolio-1-database-design/run_p1.sh
# Build the schema, run the seed, run the bulk generator, run the constraint tests.
# Idempotent — re-running rebuilds from scratch. Uses Unix socket (no password).
set -euo pipefail

PSQL="sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -v ON_ERROR_STOP=1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

$PSQL -q -c "ALTER DATABASE ironcore SET timezone TO 'Africa/Lagos'"
echo "==> [1/4] Building schema (schema.sql)"
$PSQL -f "$DIR/schema.sql"

echo "==> [2/4] Loading seed (seed.sql)"
$PSQL -f "$DIR/seed.sql"

echo "==> [3/4] Generating bulk data (generate_bulk.sql) — 6,000 members, ~7,000 memberships, ~7,400 sessions, 60,000+ bookings"
$PSQL -f "$DIR/generate_bulk.sql"

echo "==> [4/4] Running constraint tests (constraint_tests.sql)"
$PSQL -f "$DIR/constraint_tests.sql"

echo
echo "==> P1 complete. Open portfolio-1-database-design/README.md for what to screenshot and commit."
