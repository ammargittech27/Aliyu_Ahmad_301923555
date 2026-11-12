# Portfolio 5 — Distributed & Cloud Database Exercise

**Case study:** IronCore Fitness — distributed across five branches in four Nigerian
cities. The member app's "class timetable" is the heaviest read path; booking writes
go through one Lagos primary. Everything stays inside Nigeria to comply with NDPA 2023.

**Study sessions applied:** Session 17 (distributed databases — replication,
partitioning, sharding) · Session 18 (CAP theorem & consistency trade-offs) ·
Session 19 (cloud deployment & data sovereignty — NDPA 2023 Nigeria) · Session 20
(high availability & disaster recovery).

## Files

| File                    | Purpose                                                              |
|-------------------------|----------------------------------------------------------------------|
| `partition.sql`         | Rebuilds `class_booking` as a monthly RANGE-partitioned table on `class_date` (2 years + next 14 days = 25 partitions + default). Re-creates the P1 triggers on the partitioned parent. |
| `replica_setup.sh`      | Configures the primary for streaming replication, creates the `replicator` role, runs `pg_basebackup` with a physical slot, writes the replica's own `postgresql.conf` (Codespaces rule), copies `pg_hba.conf`/`pg_ident.conf`, starts the replica on port 5433 with `hot_standby=on`. Idempotent. |
| `replica_demo.sql`      | Single psql script using `\connect` to switch between primary (5432) and replica (5433). Shows: replica is in recovery, INSERT on replica is rejected with "read-only transaction", new row inserted on primary arrives on replica. |
| `cloud_architecture.md` | Lagos primary + Lagos replica + Abuja replica (DR), MongoDB replica set. CAP choices (CP for bookings, AP for timetable and workout logs). Sync vs async trade-off. January rush handling. NDPA 2023 — data stays in Nigeria. |
| `run_p5.sh`             | runs the partition + replica setup + demo                              |

## Codespaces commands

```bash
bash setup.sh                                            # one-off
bash portfolio-1-database-design/run_p1.sh               # P1 first (P5 needs the schema + data)
# Then:
bash portfolio-5-distributed-cloud/run_p5.sh             # P5 end-to-end
```

## What to screenshot

1. The list of partitions from `partition.sql`:
   ```
   SELECT pg_inherits.inhrelid::regclass FROM pg_inherits ... WHERE parent.relname='class_booking';
   ```
   should show 25 monthly partitions + `class_booking_default`.
2. The "Row counts per partition" output showing the heaviest months (e.g. January
   partitions have more rows).
3. The `pg_stat_replication` row showing `state=streaming`, `sync_state=async`,
   `sent_lsn` and `replay_lsn`.
4. `pg_is_in_recovery()` returning `t` on the replica.
5. **The replica rejecting an INSERT** with:
   ```
   ERROR:  cannot execute INSERT in a read-only transaction
   ```
6. **A new row arriving on the replica**: a `COUNT(*)` on the replica before and
   after inserting on the primary (the count increments on the replica after a
   short streaming delay).
7. `pg_last_wal_receive_lsn()` and `pg_last_wal_replay_lsn()` on the replica
   (lag in bytes).

## Git commit

```bash
git add portfolio-5-distributed-cloud/ && \
  git commit -m "P5: monthly partitioning of class_booking, streaming read replica on 5433 (writes rejected, replication demonstrated), NDPA 2023 cloud design"
```

## What this demonstrates

- **Partitioning** a hot transactional table by month with partition-pruning-friendly
  queries; the trigger logic for capacity / waitlist / membership re-applied to the
  partitioned parent.
- **Streaming replication** end-to-end: `pg_basebackup` with a replication slot, a
  separate data dir, own `postgresql.conf`, copied `pg_hba.conf`/`pg_ident.conf`,
  `chmod 700`, `standby.signal`, `hot_standby=on` — exactly the Codespaces rules in
  the brief.
- **`psql \connect` switching** between primary and replica inside one script — no
  two-terminal setup needed to demonstrate the read-only behavior and the
  propagation.
- **CAP and sync vs async** reasoning applied to a real workload (booking writes =
  CP; timetable reads = AP; workout logs = AP), grounded in the Lagos/Abuja
  Nigeria-resident topology.
- **NDPA 2023** data-residency decisions: every store is in Nigeria, no off-site
  backup to a non-Nigerian region, DPIA required for the body-measurements
  collection, cross-border transfers none, data-subject-rights procedure sketched.


## Honest note on partitioning
At about 79k rows the partitioned table is NOT faster than the unpartitioned copy with an index on `class_date`.
The plan shows **partition pruning** (`Subplans Removed`: only the matching month is read), which is what pays
off at millions of rows and for dropping old months cheaply. `replication_output.log` has the real primary/replica demo.
