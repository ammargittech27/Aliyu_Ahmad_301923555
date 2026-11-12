# CHANGES.md - IronCore Fitness (Ahmad Aliyu Bello, 2026/A/MIT/0537)

Tested in a Codespaces-like environment (Ubuntu, PostgreSQL 16, MongoDB 8, user `codespace` with root-only sudo).
Ahmad's AI drafted the project; Claude tested and fixed it (this file lists every change); Ahmad runs it in his own Codespace.

## How to run (one box)
1. Create a **private** GitHub repo with a README, open a Codespace on it.
2. Drag `Ahmad_Aliyu_Bello_FIXED.zip` and `runall.sh` into the repo root.
3. In the terminal: `bash runall.sh` (resume with `bash runall.sh 3` if it stops at P3).
4. When it finishes, open `my_results.txt`, Ctrl+A, Ctrl+C, paste it to Joseph.

## Fixes
| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | P1 `generate_bulk.sql` | `ON COMMIT DROP` temp tables were dropped at once -> `relation "_first_names" does not exist` | Removed `ON COMMIT DROP` | names load |
| 2 | P1 `generate_bulk.sql` | PL/pgSQL variables named like columns (`plan_id`, `member_id`) -> `column reference is ambiguous`; row-by-row loops were slow and fragile | Rewrote memberships, sessions and bookings as set-based SQL | 6,000 members, 7,000 memberships, 5,700 sessions, 78,790 bookings in about 2 s; 0 sessions over capacity |
| 3 | P1 `generate_bulk.sql` | Gender did not match first name; history only, `capacity` risk | Gender set from the first name; sessions = last 365 days + next 14 days, 3 per branch per day in Lagos time | realistic, future classes exist |
| 4 | P1 `constraint_tests.sql` | Tests printed a hard-coded "PASS" even when the wrong error fired (test 4 hit the membership trigger, test 7 crashed with "more than one row") | Rewrote all 7 tests: own data, expect the exact constraint, control insert that must succeed, stop on FAIL | 7/7 pass |
| 5 | P1 `run_p1.sh`, `setup.sh` | DB time zone was UTC in Codespaces | `ALTER DATABASE ironcore SET timezone TO 'Africa/Lagos'` | consistent dates |
| 6 | P2 `indexes.sql` | `BRIN ((start_time::date))` -> `functions in index expression must be marked IMMUTABLE`, P2 stopped | Replaced by 5 plain B-tree indexes | created |
| 7 | P2 queries | `DATE(start_time)=CURRENT_DATE` cannot use an index; every query read the whole history so indexes could not matter | 4 selective queries (today, 7 days, one trainer, one member) + 2 full aggregates kept on purpose; sargable range filters | Q1 0.64 -> 0.28 ms, Q4 1.21 -> 0.98 ms, Q6 3.40 -> 0.60 ms; Q2/Q3 unchanged (honest) |
| 8 | P2 `run_p2.sh` | BEFORE run already had the P1 indexes; not re-runnable; no summary | Drops all secondary indexes + `ANALYZE` first, writes `output/explain_summary.txt`, restores P1 indexes | fair, re-runnable |
| 9 | P3 `transactions.sql` | `SELECT m.member_id INTO m FROM member` (variable named like alias) crashed; `cancel_booking` reported the wrong "promoted" row; ROLLBACK demo not deterministic | Fixed names, correct promoted row, two clear ROLLBACK examples | runs |
| 10 | P3 demos | Race / isolation / deadlock only as hand-typed two-terminal steps | New `run_race_demos.py` (two real psycopg sessions + threads), `race_setup.sql` builds its own class | Real output: 21/20 overbooked bug, UNIQUE block, `FOR UPDATE` wait, SERIALIZABLE 40001, RC vs RR, deadlock 40P01 |
| 11 | P4 `schema_validation.js` | `Unknown $jsonSchema keyword: const`; `additionalProperties:false` without `_id`; strict `long/int/double` types rejected plain numbers | `enum` instead of `const`, `_id` allowed, `bsonType: "number"`; added 1 good + 2 bad test documents | 1 accepted, 2 rejected (code 121) |
| 12 | P4 `generate_data.js`, `create_index.js` | `NumberLong()` deprecation warnings; full explain JSON dumped to the screen | Plain numbers; compact `executionStats` line | 42,000 workouts; COLLSCAN 42,000 docs -> IXSCAN 10 docs |
| 13 | P5 `partition.sql` | `class_session_id is ambiguous`; a failed run left `class_booking` dropped; no way to re-run | Rewritten: builds from a copy, PK/UNIQUE include `class_date`, 14 monthly partitions + DEFAULT (0 rows), triggers and view re-created, skipped if already partitioned | 78,790 rows partitioned; pruning shown |
| 14 | P5 `replica_demo.sql` | Used `\connect "host=..."` conninfo and a broken `dblink_exec` placeholder block; BEFORE trigger cannot move a row between partitions | One script using positional `\connect`, real who-is-who, write rejected on the replica, insert on primary, row arrives, lag, `pg_stat_replication`; caller supplies `class_date` | insert rejected on replica (read-only), row streamed, replay lag < 1 ms |
| 15 | P5 `replica_setup.sh` | `pg_basebackup -C` fails if the slot already exists (re-run) | Drops an inactive old slot first | re-runnable |
| 16 | `setup.sh` | Mongo apt line hard-coded `jammy`; mongod start via systemctl (none in Codespaces); psycopg2 never installed (pip `--user` fails in Codespaces) | Codename detected, mongod started with `runuser`, pip fallback chain + import check | OK |
| 17 | docs / READMEs | `[paste real result here]` placeholders; ER paths | Replaced with pointers to the real output files | no placeholders |

## Cut to keep it fast
- Bulk load sized to about 79k bookings (clears 50k) and 42k Mongo documents; the whole run takes about 20 s here.
- Removed the revenue-per-plan and top-5 bonus queries and the advisory-lock automation (the manual `.md` walkthrough still covers it).

## Notes for the defence
- Under READ COMMITTED the capacity trigger does not stop the race (it cannot see the other session's uncommitted row): the demo shows 21/20. The fixes are the class-row lock (`FOR UPDATE`) or SERIALIZABLE.
- At about 79k rows the partitioned table is not faster than the unpartitioned copy; the plan shows pruning (only one month read), which pays off at larger scale.
- Run P3 before P5 (P5 adds the `class_date` column to `class_booking`).
