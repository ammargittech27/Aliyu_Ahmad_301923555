#!/usr/bin/env bash
# portfolio-3-transactions-concurrency/run_p3.sh — builds book_class()/cancel_booking(), runs COMMIT/ROLLBACK
# examples, then runs ALL SIX race/isolation/deadlock demos with two real sessions. Output: p3_output.log
# and race_demos_output.log.
set -euo pipefail
PSQL="sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -v ON_ERROR_STOP=1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "==> [1/3] Procedures + COMMIT/ROLLBACK examples (transactions.sql)"
$PSQL -f "$DIR/transactions.sql"
echo "==> [2/3] Race fixture (race_setup.sql)"
$PSQL -f "$DIR/race_setup.sql"
echo "==> [3/3] Six concurrency demos with two sessions (run_race_demos.py)"
python3 "$DIR/run_race_demos.py" 2>&1 | tee "$DIR/race_demos_output.log"
echo "==> P3 complete. Evidence: portfolio-3-transactions-concurrency/race_demos_output.log"
