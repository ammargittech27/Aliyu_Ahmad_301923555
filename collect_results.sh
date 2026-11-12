#!/usr/bin/env bash
# collect_results.sh - gathers the REAL output of your own run into my_results.txt (nothing is typed in by hand).
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
OUT=my_results.txt
P1=portfolio-1-database-design; P2=portfolio-2-query-optimisation; P3=portfolio-3-transactions-concurrency; P4=portfolio-4-nosql; P5=portfolio-5-distributed-cloud
sec() { echo; echo "=================== $1 ==================="; }
show() { if [ -s "$1" ]; then cat "$1"; else echo "(no $1 - this portfolio did not run)"; fi; }
{
echo "MIT 8103 results - Ahmad Aliyu Bello (2026/A/MIT/0537) - generated $(date '+%Y-%m-%d %H:%M %Z')"
echo "Host: $(uname -sr) | $(psql --version 2>/dev/null | head -1) | mongod $(mongod --version 2>/dev/null | head -1)"
sec "P1 - row counts, booking status, capacity check"
[ -s $P1/p1_output.log ] && sed -n '/Bulk generation complete/,/sessions over capacity/p' $P1/p1_output.log | grep -v '^(' || echo "(no $P1/p1_output.log)"
sec "P1 - constraint tests"
[ -s $P1/p1_output.log ] && grep -E "NOTICE:.*(PASS|control OK)|All 7 constraint tests passed|FAIL" $P1/p1_output.log | sed 's/^psql:[^ ]* NOTICE: *//' || echo "(no log)"
sec "P2 - before/after (ms and access paths, from EXPLAIN ANALYZE)"
show $P2/output/explain_summary.txt
sec "P3 - transactions + six concurrency demos (two real sessions)"
[ -s $P3/p3_output.log ] && grep -E "book_class OK|members_(before|inside_tx|after_rollback)|PASS: rejected" -A0 $P3/p3_output.log | head -8
show $P3/race_demos_output.log
sec "P4 - MongoDB: validation tests, document counts, COLLSCAN to IXSCAN"
if [ -s $P4/p4_output.log ]; then grep -E "^PASS|^FAIL|Generated|inserted|documents|Before|After" $P4/p4_output.log; else echo "(no $P4/p4_output.log)"; fi
sec "P5 - partitions, pruning timing, replica"
if [ -s $P5/partition_output.log ]; then grep -E "class_booking_20|DEFAULT partition|total rows|Subplans Removed|Execution Time|Planning Time|Seq Scan on class_booking|Index Scan using idx_flat" $P5/partition_output.log; else echo "(no $P5/partition_output.log)"; fi
echo; show $P5/replication_output.log
} > "$OUT" 2>&1
echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
