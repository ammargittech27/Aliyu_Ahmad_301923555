# Before / After indexing — IronCore Fitness P2

Real numbers are written by `run_p2.sh` to `output/explain_summary.txt` (and the full plans to
`output/explain_before.out` / `explain_after.out`). `run_p2.sh` first DROPS every secondary index and runs
`ANALYZE`, so the BEFORE run is fair and the script can be re-run.

| Query | Type | What to look for |
|---|---|---|
| Q1 free places today | selective (one day) | `Seq Scan on class_session` -> `Index Scan using p2_session_start`; bookings via `p2_booking_session` |
| Q2 fill rate per class type | full history | still `Seq Scan` on `class_booking`: an index cannot help a query that reads every row |
| Q3 busiest hours | full history | same - kept on purpose to show where indexes do NOT help |
| Q4 expiring in 7 days | selective | `Seq Scan on membership` -> `Bitmap Index Scan on p2_membership_end` |
| Q5 one trainer, 90 days | selective | the P1 GiST index `no_overlap_trainer` already served it; `p2_session_trainer_ts` replaces it; the join to ~79k bookings still scans, so the gain is small |
| Q6 one member's history | selective | `Seq Scan on class_booking` -> `Bitmap Index Scan on p2_booking_member` (largest gain) |

Report differences smaller than run-to-run noise (about 1 ms) as "no real change" when the plan did not change.
