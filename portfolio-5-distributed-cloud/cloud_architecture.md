# Cloud architecture & data-residency design — IronCore Fitness (NDPA 2023)

## 1. Why a distributed / cloud setup?

IronCore has branches in **Abuja (Wuse, Gwarinpa), Kano, Kaduna, Lagos (Lekki)**. The
member app needs to read the **class timetable** (the next 14 days of sessions across
all branches) hundreds of times per second during the **January sign-up rush**. The
core booking writes go through one primary in Lagos; the member-app reads can be
served by a streaming read replica in Lagos plus a cross-region read replica in Abuja.
All data stays inside Nigeria to comply with the **Nigeria Data Protection Act 2023
(NDPA 2023)**.

## 2. Topology

```
                          ┌──────────────────────────────────────────────┐
                          │  Lagos region  (primary, AZ-1)               │
                          │  PostgreSQL 16 primary, port 5432             │
                          │  - writes: bookings, memberships, payments    │
                          │  - DB: ironcore                              │
                          └───────────────┬─────────────┬────────────────┘
                                          │ streaming   │ streaming (async)
                                          ▼             ▼
                          ┌──────────────────────────┐   ┌──────────────────────────┐
                          │ Lagos read replica       │   │ Abuja read replica       │
                          │ (Codespaces demo, 5433)   │   │ (production: same PG, AZ) │
                          │ member app: timetable     │   │ admin reports, backups    │
                          └──────────────────────────┘   └──────────────────────────┘

                          ┌─────────────────────────────────────────────┐
                          │  MongoDB replica set — primary in Lagos      │
                          │  - workout logs, trainer notes, measurements  │
                          │  - 2 secondaries (Lagos + Abuja)             │
                          └─────────────────────────────────────────────┘
```

- **PostgreSQL primary** (Lagos) — only writer.
- **Lagos read replica** (the one built in this portfolio) — serves the member-app's
  "class timetable" reads (today + next 14 days). Asynchronous streaming replication,
  RPO ~0 seconds on the same LAN.
- **Abuja read replica** (production only, not built in the demo) — disaster-recovery
  + low-latency reads for the Abuja branches.
- **MongoDB replica set** — primary in Lagos, two secondaries; reads use
  `secondaryPreferred` for analytics so the primary is reserved for workout-log writes.

## 3. CAP theorem and what we give up

CAP says: in the presence of a network partition, you must choose **Consistency** or
**Availability**.

| Subsystem                  | CAP choice      | Why                                                                  |
|----------------------------|-----------------|----------------------------------------------------------------------|
| Booking writes (primary)   | **C + P**       | Money + capacity invariants cannot be sacrificed; if the primary is partitioned from replicas, the primary keeps accepting writes and replicas stall. CP. |
| Member-app timetable reads | **A + P**       | The timetable is served from the replica; if the replica is partitioned from the primary, it stays available with the latest committed data it has. Slightly stale; AP. The "stale-by-default" rule is acceptable for a class timetable (members know capacity can change in real time). |
| Workout logs (MongoDB)     | **A + P**       | Replica set with `w=1, wtimeout=0` and `readPreference=secondaryPreferred`. Under a partition, the primary accepts writes and a minority-side secondary serves stale reads. AP, tunable towards CP with `w=majority`. |

For bookings we explicitly choose **CP** because the alternative is over-booking
(or worse, lost payments). For the timetable and workout logs we choose **AP**
because stale reads there are tolerable and the user experience is much worse if
the app is down.

## 4. Sync vs async replication trade-off

| Trade-off                  | Synchronous (`synchronous_commit = on`, `synchronous_standby_names`) | Asynchronous (default) |
|----------------------------|---------------------------------------------------------|------------------------|
| RPO on partition           | 0 (no data loss)                                       | seconds-to-minutes of data loss possible |
| Write latency              | + 1 RTT to standby (Lagos→Abuja is ~5-15 ms; Lagos→Lagos LAN < 1 ms) | No added latency |
| Availability under standby outage | Primary stalls writes until the sync standby is back | Primary keeps writing |
| Use case                   | Money, payments, the "last booking" decision            | Analytics replicas, the timetable, workout logs |

For IronCore:
- **The Lagos primary → Lagos replica** link is **synchronous** for the booking path
  only (a single sync standby, the Lagos replica). The wait is a sub-millisecond
  LAN RTT, so writes still feel fast.
- **The Lagos → Abuja link** is **asynchronous** so the Abuja WAN latency does not
  slow down Lagos writes.
- **MongoDB** uses `w=majority` for workout logs (cheap on a 3-node replica set with
  two secondaries in the same datacenter).

## 5. Partitioning strategy

`class_booking` is **RANGE-partitioned by `class_date` (monthly)** — see
`partition.sql`. Two years of history + the next 14 days live in 25 monthly
partitions plus a DEFAULT catch-all. Benefits:

- **Maintenance**: `VACUUM`/`ANALYZE`/`REINDEX` operate per partition, so the monthly
  archiving task can run on the oldest partition only.
- **Query pruning**: P2's `WHERE DATE(s.start_time) = CURRENT_DATE` query needs to
  scan only the current month's partition — the planner can prune the other 24 away
  because `class_date` is the partition key.
- **Drop old data cheaply**: `DROP TABLE ironcore.class_booking_2024_01` is a metadata
  operation; we don't have to `DELETE` rows.
- **Writes still go to the parent**: `INSERT INTO class_booking` routes to the correct
  child partition automatically. The trigger logic (capacity, waitlist promotion,
  membership check) works on the parent table.

## 6. The January sign-up rush

Empirically, Nigerian gyms see a 3-4x spike in sign-ups and class bookings in
January (new-year resolutions). The bulk generator in P1 deliberately weights
January bookings 1.3x. The architecture must absorb this:

1. **Read scaling.** The member-app timetable is read-heavy and read-only. The Lagos
   read replica (port 5433 in this demo) is added behind a load balancer (PgBouncer
   in transaction-pooling mode). In production we would add 2-3 Lagos replicas + the
   Abuja replica, all serving the timetable. Reads scale linearly with replica count.
2. **Write scaling.** Booking writes are not horizontally scalable on PostgreSQL
   without sharding; instead, we:
   - Keep the **primary on the largest instance class** (e.g. AWS RDS `db.r7g.4xlarge`
     equivalent) for January, downsize for the rest of the year.
   - Use **`pg_advisory_xact_lock(class_session_id)`** to serialise only writers on the
     same class, not all writers globally (see P3).
   - **Partition pruning** means January's inserts touch only the
     `class_booking_2027_01` partition; the locks and indexes for the other months
     are not touched at all.
3. **Connection pooling.** PgBouncer in front of the primary, transaction-pooling
   mode, so 10,000 simultaneous member-app connections multiplex onto ~50 backend
   connections. Each January rush spike hits PgBouncer, not the primary's process
   limit.
4. **MongoDB side.** Workout logs are also peaky in January (new members log their
   first sessions). The replica set is provisioned with two secondaries and
   `readPreference=secondaryPreferred` for analytics so the primary is reserved for
   writes.
5. **Queue-based write throttle.** If the primary's WAL backlog grows during the
   peak, the booking service writes to a Kafka topic first; a worker drains it
   into PostgreSQL at a controlled rate. The member app shows "your booking is being
   confirmed" while the row is still in the queue. (Architectural note; not
   implemented in this portfolio.)

## 7. NDPA 2023 — data sovereignty

The Nigeria Data Protection Act 2023 requires that **personal data of Nigerian
residents is stored and processed in Nigeria unless an adequacy decision or
appropriate safeguards exist**. IronCore's data is sensitive: members' names,
emails, phone numbers, dates of birth, body measurements and workout history.

Concrete decisions:

- **Region**: Lagos + Abuja, both inside Nigeria. No AWS us-east-1, no EU Frankfurt
  fallback. The primary PostgreSQL cluster and the MongoDB replica set primary both
  live in a Lagos datacenter; the Abuja replica is in a separate Abuja datacenter
  inside Nigeria.
- **Backups**: encrypted at rest with a Nigerian-held KMS key; no off-site backup to
  a non-Nigerian S3 bucket. Restore drills are performed quarterly.
- **Cross-border transfer**: none. If a trainer in Ghana needs to view a member's
  note, the request is routed to the Lagos primary; no copy of the data is held
  outside Nigeria.
- **DPIA**: a Data Protection Impact Assessment is performed under NDPA 2023 before
  the body-measurements collection is launched (the "biometric-ish" data is in
  `body_measurements`).
- **Data subject rights**: NDPA 2023 grants access / rectification / erasure. A
  stored procedure `ironcore.dissolve_member(p_member_id)` cascades the deletion
  to `member`, `membership`, `class_booking`, `payment`, MongoDB `workouts`,
  `trainer_notes`, `body_measurements` — implemented in a follow-up task, not in
  this portfolio.
- **Audit**: a `data_access_log` table records every read of PII by an admin user
  (out of scope here).

## 8. Connection-string summary

- **Primary**: `postgresql://<user>@/ironcore?host=/var/run/postgresql&port=5432`
  (Codespaces — Unix socket, trust)
- **Replica**: `postgresql://<user>@/ironcore?host=/var/run/postgresql&port=5433`
  (Codespaces demo) — read-only.
- **Mongo**: `mongodb://127.0.0.1:27017/ironcore_gym` (Codespaces demo). Production:
  `mongodb://<user>:<pass>@mongo-lagos-primary.ironcore.ng:27017,mongo-lagos-sec1.ironcore.ng:27017,mongo-abuja-sec2.ironcore.ng:27017/ironcore_gym?replicaSet=rs0&readPreference=secondaryPreferred`

## 9. References

- NDPA 2023 — Nigeria Data Protection Act, 2023
  <https://ndpc.gov.ng/wp-content/uploads/2023/06/Nigeria-Data-Protection-Act-2023.pdf>
- PostgreSQL 16 — High Availability, Load Balancing, and Replication
  <https://www.postgresql.org/docs/16/high-availability.html>
- PostgreSQL 16 — Table Partitioning
  <https://www.postgresql.org/docs/16/ddl-partitioning.html>
- MongoDB 8 — Replica Sets
  <https://www.mongodb.com/docs/manual/replication/>
- Kleppmann, *Designing Data-Intensive Applications* — chapters 5 (replication) and
  6 (partitioning), which frame the CAP + sync-vs-async discussion.
