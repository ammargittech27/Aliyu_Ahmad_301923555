#!/usr/bin/env bash
# portfolio-2-query-optimisation/run_p2.sh — fair, re-runnable BEFORE/AFTER comparison.
# Drops every secondary index first (so BEFORE really has none), runs ANALYZE, times the 6 queries,
# adds the P2 indexes, runs ANALYZE, times again, then writes output/explain_summary.txt.
set -euo pipefail
PSQL="sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -v ON_ERROR_STOP=1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/output"; mkdir -p "$OUT"; cd "$DIR"

echo "==> [1/5] Running queries.sql (results)"
$PSQL -f queries.sql > "$OUT/queries.out" 2>&1; tail -n 12 "$OUT/queries.out"

echo "==> [2/5] Dropping secondary indexes + ANALYZE (so BEFORE has no helper indexes)"
$PSQL -q -c "DO \$\$ DECLARE r record; BEGIN FOR r IN SELECT indexname FROM pg_indexes WHERE schemaname='ironcore' AND indexname ~ '^(idx_|p2_)' LOOP EXECUTE 'DROP INDEX ironcore.'||quote_ident(r.indexname); END LOOP; END \$\$; ANALYZE;"

echo "==> [3/5] EXPLAIN ANALYZE BEFORE"
$PSQL -f explain_before.sql 2>&1 | tee "$OUT/explain_before.out" >/dev/null

echo "==> [4/5] Creating indexes + ANALYZE, then EXPLAIN ANALYZE AFTER"
$PSQL -f indexes.sql 2>&1 | tee "$OUT/indexes.out"
$PSQL -q -c "ANALYZE;"
$PSQL -f explain_after.sql 2>&1 | tee "$OUT/explain_after.out" >/dev/null

echo "==> [5/5] Summary (real numbers from this run)"
summ() { awk -v ph="$2" '/^== Q[0-9]/{q=$2} /Execution Time/{t[q]=$3} /Seq Scan on|Index Scan using|Index Only Scan using|Bitmap Index Scan on/{gsub(/^[ ->]+/,"");sub(/ \(actual.*/,"");a[q]=a[q] "; " $0} END{for(i=1;i<=6;i++){k="Q" i; printf "%s %s  %s ms  %s\n", ph, k, t[k], substr(a[k],3)}}' "$1"; }
{ echo "P2 summary (ms from EXPLAIN ANALYZE; access paths taken):"; summ "$OUT/explain_before.out" BEFORE; echo; summ "$OUT/explain_after.out" AFTER; } | tee "$OUT/explain_summary.txt"
# restore the P1 secondary indexes so later portfolios see the normal schema
$PSQL -q -c "SET search_path=ironcore; CREATE INDEX IF NOT EXISTS idx_booking_session ON class_booking(class_session_id); CREATE INDEX IF NOT EXISTS idx_booking_member ON class_booking(member_id); CREATE INDEX IF NOT EXISTS idx_class_session_time ON class_session(start_time); CREATE INDEX IF NOT EXISTS idx_membership_member ON membership(member_id);"
echo "==> P2 complete. Output in $OUT/ (explain_summary.txt has the before/after times)."
