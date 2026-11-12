# Race condition — "last spot in a class"

This document walks through the classic **lost update / over-booking** race on the
`ironcore.class_booking` table. It is intended to be run as **two interactive `psql`
sessions side-by-side** (two Codespaces terminals or two panes inside `tmux`).

> Setup reminder: all sessions connect over the Unix socket, no password.
> ```bash
> # terminal A
> sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore
> # terminal B (same command, in another pane)
> sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore
> ```

`psql` `\gset` captures a SELECT result into a `psql` variable, so we never copy ids by
hand. All ids are referenced as `:varname` after `\gset`.

The race: a class has capacity 20 and currently 19 BOOKED. Two members both try to book
the last spot at the same time.

The class_session used by all three demos is prepared once at the top of `race_setup.sql`
— **run it once on one terminal** before each demo, so each demo starts from a clean state.

---

## 0. One-time setup (run once on Terminal A)

```bash
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore \
  -f portfolio-3-transactions-concurrency/race_setup.sql
```

`race_setup.sql` creates a class_session with capacity 20, fills it with 19 BOOKED
rows, and prints two members (`member_id_a`, `member_id_b`) who have an active
membership on the class day. **Remember to re-run `race_setup.sql` before each demo
(1, 2, 3) so the class is back to 19/20.**

---

## 1. The bug — both see 19/20 and both book → class ends at 21/20

This demo deliberately disables the BEFORE-INSERT `enforce_capacity` trigger so the
race is observable at the SQL level. (With the trigger on, the second INSERT would be
silently turned into WAITLISTED — the bug is *hidden* by the trigger, but it is still
there because the trigger does its own SELECT COUNT(*) outside any row lock.)

```sql
-- terminal A — disable the capacity trigger for this demo only
ALTER TABLE ironcore.class_booking DISABLE TRIGGER trg_enforce_capacity;
-- IMPORTANT: also disable the membership check so the bug is shown in isolation
ALTER TABLE ironcore.class_booking DISABLE TRIGGER trg_check_membership_before_booking;
```

Now prepare the two members in each session (run on **both** terminals):

```sql
\set ON_ERROR_STOP off
SET search_path TO ironcore, public;
\echo 'Session ready. class_session_id and member ids:'
SELECT 19 AS booked_so_far, 20 AS capacity;
```

Set up the variables in each session. In terminal A:

```sql
SELECT class_session_id AS race_session_id
FROM   class_session
WHERE  start_time > now()
ORDER BY start_time
LIMIT 1
\gset

SELECT member_id AS member_id_a
FROM   member
WHERE  EXISTS (SELECT 1 FROM membership ms
              WHERE ms.member_id = member.member_id
                AND ms.start_date <= DATE(now())
                AND ms.end_date   >= DATE(now()))
ORDER  BY member_id
LIMIT 1
\gset
```

In terminal B, repeat the same `\gset` for `race_session_id`, then grab a *different*
member:

```sql
SELECT class_session_id AS race_session_id
FROM   class_session
WHERE  start_time > now()
ORDER BY start_time
LIMIT 1
\gset;

SELECT member_id AS member_id_b
FROM   member
WHERE  EXISTS (SELECT 1 FROM membership ms
              WHERE ms.member_id = member.member_id
                AND ms.start_date <= DATE(now())
                AND ms.end_date   >= DATE(now()))
  AND  member_id <> :member_id_a
ORDER  BY member_id
LIMIT 1
\gset
```

Now the race — **interleave the two sessions**:

| Step | Terminal A                                                     | Terminal B                                                     |
|------|----------------------------------------------------------------|----------------------------------------------------------------|
| 1    | `BEGIN;`                                                       | `BEGIN;`                                                       |
| 2    | `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → returns **19** | (same) `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → returns **19** |
| 3    | Application logic decides: 19 < 20, so it INSERTs.<br>`INSERT INTO class_booking (class_session_id, member_id, status) VALUES (:race_session_id, :member_id_a, 'BOOKED');` | (same) `INSERT INTO class_booking (class_session_id, member_id, status) VALUES (:race_session_id, :member_id_b, 'BOOKED');` |
| 4    | `COMMIT;`                                                      | `COMMIT;`                                                      |
| 5    | `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → **21** ❌ | (same) → **21** ❌ |

Both sessions saw 19, both INSERTed a BOOKED row, the class is now over capacity.
**Take a screenshot showing both terminals and the count of 21.**

Re-enable the triggers:

```sql
-- terminal A (sufficient; triggers are table-level)
ALTER TABLE ironcore.class_booking ENABLE TRIGGER trg_enforce_capacity;
ALTER TABLE ironcore.class_booking ENABLE TRIGGER trg_check_membership_before_booking;
```

Reset for the next demo:

```bash
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore \
  -f portfolio-3-transactions-concurrency/race_setup.sql
```

---

## 2. Fix 1 — `SELECT ... FOR UPDATE` on the `class_session` row

Re-introduce the row lock on the parent `class_session` row inside the booking path.
Both sessions now block on the same row, so the second session sees the *new* count.

| Step | Terminal A                                                     | Terminal B                                                     |
|------|----------------------------------------------------------------|----------------------------------------------------------------|
| 1    | `BEGIN;`                                                       | `BEGIN;`                                                       |
| 2    | `SELECT capacity FROM class_session WHERE class_session_id = :race_session_id FOR UPDATE;` → returns **20**. The class_session row is now locked. | (same statement) — **blocks**, waiting for A's lock. |
| 3    | `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → **19** | (still blocked) |
| 4    | `INSERT INTO class_booking (class_session_id, member_id, status) VALUES (:race_session_id, :member_id_a, 'BOOKED');` | (still blocked) |
| 5    | `COMMIT;`                                                      | (lock released; B unblocks) → returns **20**. |
| 6    |                                                                | `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → **20**. Now full. |
| 7    |                                                                | Application decides: 20 < 20 is false — switch to waitlist path:<br>`INSERT INTO class_booking (class_session_id, member_id, status, waitlist_position) VALUES (:race_session_id, :member_id_b, 'WAITLISTED', 1);` |
| 8    |                                                                | `COMMIT;` |
| 9    | `SELECT status, waitlist_position FROM class_booking WHERE class_session_id = :race_session_id ORDER BY booking_id;` → 20 BOOKED + 1 WAITLISTED at position 1 | (same) |

Final state is correct: **20 BOOKED**, **1 WAITLISTED**. **Take a screenshot showing
the blocking on step 2 in terminal B and the final 20/1 counts.**

Why this works: `FOR UPDATE` acquires a strong exclusive lock on the row, so the
second session cannot read the row until the first commits. The two transactions
become effectively serial on the class_session row.

---

## 3. Fix 2 — `pg_advisory_xact_lock(class_session_id)`

PostgreSQL advisory locks are not tied to a specific row. They are identified by an
application-chosen 64-bit integer. `pg_advisory_xact_lock(id)` is held until the end of
the transaction and is automatically released on `COMMIT`/`ROLLBACK`.

| Step | Terminal A                                                     | Terminal B                                                     |
|------|----------------------------------------------------------------|----------------------------------------------------------------|
| 1    | `BEGIN;`                                                       | `BEGIN;`                                                       |
| 2    | `SELECT pg_advisory_xact_lock(:race_session_id);`              | `SELECT pg_advisory_xact_lock(:race_session_id);` — **blocks** until A commits. |
| 3    | `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → **19** | (blocked) |
| 4    | `INSERT INTO class_booking (class_session_id, member_id, status) VALUES (:race_session_id, :member_id_a, 'BOOKED');` | (blocked) |
| 5    | `COMMIT;`                                                      | (lock auto-released; B unblocks) → `pg_advisory_xact_lock` returns. |
| 6    |                                                                | `SELECT COUNT(*) FROM class_booking WHERE class_session_id = :race_session_id AND status='BOOKED';` → **20**. Full. |
| 7    |                                                                | `INSERT INTO class_booking (class_session_id, member_id, status, waitlist_position) VALUES (:race_session_id, :member_id_b, 'WAITLISTED', 1);` |
| 8    |                                                                | `COMMIT;` |
| 9    | `SELECT status, waitlist_position FROM class_booking WHERE class_session_id = :race_session_id;` → 20 BOOKED + 1 WAITLISTED | (same) |

Final state is correct. **Take a screenshot showing terminal B blocked on
`pg_advisory_xact_lock`, then unblocked after terminal A's `COMMIT`.**

### When is an advisory lock better than a row lock?

| Situation                                                            | Use            |
|----------------------------------------------------------------------|----------------|
| You lock a real row that the transaction also updates                | `FOR UPDATE` — works, lock is freed at COMMIT |
| You want to serialise work *without* touching the row (no SELECT/UPDATE on the parent) | `pg_advisory_xact_lock` — saves a row read, no WAL writes |
| The resource you serialise on does **not exist** as a row in the DB (e.g. "distribute class_session_id across workers") | `pg_advisory_xact_lock` — only option |
| You need a lock that survives `COMMIT` (long-lived session lock)     | `pg_advisory_lock` (non-xact variant, must be `pg_advisory_unlock`-ed manually) |
| Many short transactions per second all hitting the same row          | `pg_advisory_xact_lock` is lighter — no row-level lock manager contention |

For IronCore: booking the last spot in a class is a textbook fit for
`pg_advisory_xact_lock(class_session_id)` — we don't actually need to update the
`class_session` row, only serialise writers on it. It avoids the row-lock
manager overhead when many members book the same popular spinning class in the
same second.

---

## How to capture the screenshots

- Codespaces: open two terminals side-by-side (split the editor view).
- Run `race_setup.sql` before each demo to reset to 19/20.
- For Fix 1 and Fix 2, run the two sessions step-by-step. The blocking is visible:
  terminal B's prompt does not return after step 2 until terminal A reaches `COMMIT`.
