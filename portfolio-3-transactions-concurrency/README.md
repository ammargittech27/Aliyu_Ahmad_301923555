# Portfolio 3 — Transactions & Concurrency

**Case study:** IronCore Fitness — booking a class is a multi-step transaction
(check membership → check capacity → insert booking or waitlist). Cancelling a
booking must promote the next waitlist member atomically.

**Study sessions applied:** Session 10 (transaction management & ACID) · Session 11
(isolation levels) · Session 12 (locking — row, advisory, `FOR UPDATE`) · Session 13
(deadlocks & recovery).

## Files

| File                    | Purpose                                                      |
|-------------------------|--------------------------------------------------------------|
| `transactions.sql`      | `ironcore.book_class()` and `ironcore.cancel_booking()` PL/pgSQL stored procedures + COMMIT/ROLLBACK example |
| `race_setup.sql`        | prepares a 19/20 full class + eligible members for the demos |
| `race_condition_demo.md`| step-by-step two-terminal walkthrough: the bug, fix 1 (`FOR UPDATE`), fix 2 (`pg_advisory_xact_lock`), when each is better |
| `isolation_levels.md`   | two-terminal READ COMMITTED vs REPEATABLE READ demo + retry sketch |
| `deadlock_demo.md`      | two-terminal deadlock demo (acquire locks in opposite order)|
| `run_p3.sh`             | builds the procedures + prepares the race session              |

## Codespaces commands

```bash
bash portfolio-3-transactions-concurrency/run_p3.sh   # builds procedures + prepares race session
# Then, in two psql terminals side-by-side:
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore
#   and follow portfolio-3-transactions-concurrency/race_condition_demo.md
#   then isolation_levels.md
#   then deadlock_demo.md
#   re-run race_setup.sql between demos:
bash portfolio-3-transactions-concurrency/run_p3.sh
```

> **Automatic run:** `run_p3.sh` now runs all six demos (bug, UNIQUE, `FOR UPDATE`, SERIALIZABLE,
> READ COMMITTED vs REPEATABLE READ, deadlock) with two real sessions and saves the real output in
> `race_demos_output.log`. The `.md` walkthroughs remain as the manual two-terminal version (including the
> advisory-lock variant). Run P3 before P5: P5 re-creates `class_booking` with a `class_date` column.

## What to screenshot

0. `race_demos_output.log` (all six parts in one file).

1. **Race — bug.** Two terminals both seeing 19 BOOKED, both INSERTing a BOOKED row,
   final count = 21 (over-capacity).
2. **Race — fix 1.** Terminal B blocked on `SELECT ... FOR UPDATE`, then unblocked
   after Terminal A's `COMMIT`. Final state = 20 BOOKED + 1 WAITLISTED.
3. **Race — fix 2.** Terminal B blocked on `pg_advisory_xact_lock`, unblocked after
   A's `COMMIT`. Same final state.
4. **Isolation — READ COMMITTED.** Terminal A reads capacity 20 then 25 in the same
   transaction.
5. **Isolation — REPEATABLE READ.** Terminal A reads capacity 25 both times; the
   UPDATE raises `could not serialize access due to concurrent update`.
6. **Deadlock.** Terminal A gets `ERROR: deadlock detected`. Terminal B's UPDATE
   succeeds.

## Git commit

```bash
git add portfolio-3-transactions-concurrency/ && \
  git commit -m "P3: book_class/cancel_booking txns, race condition (bug + FOR UPDATE + advisory lock), isolation levels, deadlock demo"
```

## What this demonstrates

- ACID transactions wrapped as PL/pgSQL stored procedures (`book_class`,
  `cancel_booking`) — atomic multi-step business logic.
- The classic over-booking race, reproduced by disabling the safety trigger; then two
  real fixes (row lock vs. advisory lock) — and a discussion of when each is better.
- The READ COMMITTED vs REPEATABLE READ trade-off, demonstrated, not just described.
- A real PostgreSQL `deadlock detected` error, reproduced by acquiring row locks in
  opposite order, and the standard `deadlock_detected → retry` pattern.
- No `pg_sleep()` hacks — all blocking is natural (lock waits).
- `psql \gset` variables are used for all ids, so the steps are copy-paste safe; no
  "paste the id from the other terminal here" instructions.
