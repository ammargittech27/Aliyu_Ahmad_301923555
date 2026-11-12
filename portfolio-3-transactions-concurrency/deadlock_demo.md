# Deadlock demo — two sessions acquire locks in opposite order

A deadlock is a circular lock dependency: A waits on B, B waits on A. PostgreSQL
detects this within ~1 second (configurable via `deadlock_timeout`) and aborts one
of the two transactions. The other one can then proceed.

This demo uses **two members and two class_sessions**. Each terminal locks one
booking row, then tries to lock the other.

---

## Setup

```bash
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore \
  -f portfolio-3-transactions-concurrency/race_setup.sql
```

Open both terminals:
```bash
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore
```

In both terminals, capture two member ids and two class_session ids:

```sql
\set ON_ERROR_STOP off
SET search_path TO ironcore, public;

-- two class_sessions starting in the future
SELECT class_session_id AS s1 FROM class_session WHERE start_time > now() ORDER BY start_time LIMIT 1 \gset
SELECT class_session_id AS s2 FROM class_session WHERE start_time > now() ORDER BY start_time LIMIT 1 OFFSET 1 \gset

-- two members with an active membership today
SELECT member_id AS m1 FROM member ORDER BY member_id LIMIT 1 \gset
SELECT member_id AS m2 FROM member ORDER BY member_id LIMIT 1 OFFSET 1 \gset
```

Make sure each (member, class) combination has a row to lock. Run this on **either**
terminal:

```sql
INSERT INTO class_booking (class_session_id, member_id, status)
VALUES (:s1, :m1, 'BOOKED'), (:s1, :m2, 'BOOKED'),
       (:s2, :m1, 'BOOKED'), (:s2, :m2, 'BOOKED')
ON CONFLICT (class_session_id, member_id) DO UPDATE SET status = 'BOOKED';
```

---

## The deadlock

| Step | Terminal A                                                     | Terminal B                                                     |
|------|----------------------------------------------------------------|----------------------------------------------------------------|
| 1    | `BEGIN;`                                                       | `BEGIN;`                                                       |
| 2    | `UPDATE class_booking SET status='BOOKED' WHERE class_session_id = :s1 AND member_id = :m1;` (locks row s1/m1) | `UPDATE class_booking SET status='BOOKED' WHERE class_session_id = :s2 AND member_id = :m2;` (locks row s2/m2) |
| 3    | `UPDATE class_booking SET status='BOOKED' WHERE class_session_id = :s2 AND member_id = :m2;` — **blocks** (B holds s2/m2) | (wait a moment, then) `UPDATE class_booking SET status='BOOKED' WHERE class_session_id = :s1 AND member_id = :m1;` — **blocks** (A holds s1/m1) |
| 4    | Within `deadlock_timeout` (~1s), PostgreSQL detects the cycle. One transaction receives:<br>`ERROR: deadlock detected`<br>`DETAIL: Process ... waits for ShareLock on transaction ... blocked by process ...` | The other transaction succeeds and **commits normally** if you `COMMIT;` |
| 5    | `ROLLBACK;` (A was aborted)                                    | `COMMIT;`                                                      |

**Screenshot:** Terminal A shows the `deadlock detected` error after step 4. Terminal
B's `UPDATE` succeeds.

---

## What the deadlock looks like

```
ERROR:  deadlock detected
DETAIL:  Process 1234 waits for ShareLock on transaction 5678, blocked by process 5679.
        Process 5679 waits for ShareLock on transaction 5677, blocked by process 1234.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (...,...) in relation "class_booking"
```

The exact `process`/`transaction` numbers will differ. Copy the **real** output into
the final PDF — do not paraphrase.

---

## How IronCore prevents this in practice

- All application booking paths acquire locks in a **consistent global order**: always
  by `(class_session_id, member_id)` ascending. The classic cause of deadlocks is
  "lock order varies by request flow"; the standard cure is to pin a single order in
  the data-access layer.
- The `book_class()` stored procedure in `transactions.sql` only locks the
  `class_session` row (single lock), so two concurrent `book_class()` calls cannot
  deadlock with each other — they just block.
- PostgreSQL detects deadlocks automatically after `deadlock_timeout` (default 1s);
  the application should retry on `deadlock_detected` (40P01), as in the retry sketch
  in `isolation_levels.md`.

## Notes for the screenshot

- Do **not** use `pg_sleep()` — the demo works because both sessions naturally
  block waiting for the same row lock.
- The deadlock detection message is printed by PostgreSQL automatically; nothing
  in the script asks for it.
