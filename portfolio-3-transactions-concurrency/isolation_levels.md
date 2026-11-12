# Isolation levels — READ COMMITTED vs REPEATABLE READ

This demo uses the same two-terminal pattern as `race_condition_demo.md`.
The class used here is the same `race_session` produced by `race_setup.sql`.

Default isolation level in PostgreSQL is **READ COMMITTED**.

---

## Setup (run on Terminal A once)

```bash
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore \
  -f portfolio-3-transactions-concurrency/race_setup.sql
```

Open both terminals:
```bash
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore
```

---

## A. READ COMMITTED — non-repeatable read is *possible*

| Step | Terminal A                                                     | Terminal B                                                     |
|------|----------------------------------------------------------------|----------------------------------------------------------------|
| 1    | `SHOW isolation_level;` → `read committed`                    | `SHOW isolation_level;` → `read committed`                    |
| 2    | `BEGIN;`                                                       | `BEGIN;`                                                       |
| 3    | `SELECT capacity FROM class_session WHERE class_session_id = :race_session_id;` → **20** | (no read) |
| 4    |                                                                | `UPDATE class_session SET capacity = 25 WHERE class_session_id = :race_session_id;` (no lock conflict — different row field) |
| 5    |                                                                | `COMMIT;` |
| 6    | `SELECT capacity FROM class_session WHERE class_session_id = :race_session_id;` → **25** (changed!) | |
| 7    | `COMMIT;`                                                      |                                                                |

Terminal A read **20**, then read **25** inside the same transaction. This is a
**non-repeatable read**. READ COMMITTED does not prevent it.

**Screenshot:** the two `SELECT capacity` lines in terminal A returning different
numbers within the same transaction.

---

## B. REPEATABLE READ — non-repeatable read is *prevented*

| Step | Terminal A                                                                   | Terminal B                                                     |
|------|------------------------------------------------------------------------------|----------------------------------------------------------------|
| 1    | `BEGIN ISOLATION LEVEL REPEATABLE READ;`                                     | `BEGIN ISOLATION LEVEL REPEATABLE READ;`                       |
| 2    | `SELECT capacity FROM class_session WHERE class_session_id = :race_session_id;` → **25** | (no read) |
| 3    |                                                                              | `UPDATE class_session SET capacity = 20 WHERE class_session_id = :race_session_id;` |
| 4    |                                                                              | `COMMIT;`                                                      |
| 5    | `SELECT capacity FROM class_session WHERE class_session_id = :race_session_id;` → **25** (unchanged — snapshot preserved) | |
| 6    | Try to update the row too: `UPDATE class_session SET capacity = 30 WHERE class_session_id = :race_session_id;` → ERROR: `could not serialize access due to concurrent update`. | |
| 7    | `ROLLBACK;` (the write conflict forces a retry)                              |                                                                |

Under REPEATABLE READ, A's snapshot was taken at the first SELECT and does **not**
see B's committed change (no non-repeatable read). However, if A tries to **write**
the row that B modified, PostgreSQL raises `could not serialize access due to
concurrent update` and the transaction must be retried.

**Screenshot:** the unchanged second SELECT in terminal A, then the
`could not serialize access` error.

---

## Why this matters for IronCore

- **Member app reading class capacity** for display: READ COMMITTED is fine — we don't
  care if the displayed capacity flips between page refreshes.
- **Booking transaction** (multi-step: check membership → check capacity → insert):
  REPEATABLE READ would give us a stable snapshot but it can throw
  `could not serialize access` if another transaction updates the same row, forcing
  retry. We accept READ COMMITTED and use the explicit row lock or advisory lock
  (see `race_condition_demo.md`) instead — that is the standard PostgreSQL pattern
  and is cheaper than full SERIALIZABLE.
- **Reporting queries** (e.g. P2's revenue-per-plan-per-month) are read-only, so the
  default READ COMMITTED is fine; they always see the latest committed snapshot.

## How to retry on `could not serialize access` (real code sketch)

```sql
-- inside an application loop:
DO $$
DECLARE attempts INT := 0;
BEGIN
    LOOP
        BEGIN
            -- ... booking transaction ...
            RETURN;
        EXCEPTION WHEN serialization_failure OR deadlock_detected THEN
            attempts := attempts + 1;
            IF attempts > 5 THEN RAISE; END IF;
            CONTINUE;
        END;
    END LOOP;
END $$;
```
