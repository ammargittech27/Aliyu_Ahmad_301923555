# SQL vs NoSQL — IronCore Fitness

The portfolio uses **both** data stores against the same case study. This file
explains why each part of IronCore lives where it does, and what the trade-offs are.

## Where each piece of data lives

| Data                                | Stored in        | Reason                                                                                              |
|-------------------------------------|------------------|-----------------------------------------------------------------------------------------------------|
| Branches, members, plans, trainers | PostgreSQL       | Strong schema, FK integrity, fixed set of attributes                                              |
| Memberships                         | PostgreSQL       | Exclusion constraint for non-overlapping time ranges — needs GiST                                  |
| Class sessions + bookings           | PostgreSQL       | Capacity is a hard invariant that must hold under concurrency — triggers + row locks + advisory locks |
| Payments                            | PostgreSQL       | ACID guarantee is non-negotiable for money; reference must be unique                               |
| Workout logs (exercises, reps, sets)| MongoDB          | Different workout types have very different fields (strength vs cardio vs flexibility). A SQL schema would need a wide table with many NULLs or three separate tables. MongoDB's `$jsonSchema` `oneOf` validates the right shape per exercise type. |
| Trainer notes                       | MongoDB          | Free-text notes with optional tags — flexible schema, growing tag set                              |
| Body measurements over time         | MongoDB          | Per-member document with a varying set of measured fields — fits a document model better than a sparse SQL row |

## Comparison

| Dimension           | PostgreSQL (SQL)                                            | MongoDB (NoSQL, document)                                           |
|---------------------|------------------------------------------------------------|----------------------------------------------------------------------|
| Schema              | Fixed by `CREATE TABLE`; ALTER TABLE required for change   | Validated at insert-time by `$jsonSchema`; can be relaxed with `validationLevel: "moderate"` |
| Joins               | Native, optimiser-driven; great for relations like member↔plan↔payment | Generally avoided; data is denormalised per document; `$lookup` exists but is heavier |
| Transactions        | Full ACID, MVCC, savepoints, serialisable                  | Multi-document ACID since 4.0 (replica sets); single-document atomic always |
| Time-overlap rules  | `EXCLUDE USING gist` — first-class in SQL                  | No equivalent — must be enforced in application code or via $jsonSchema pre-write |
| Concurrency control | Row locks, advisory locks, `FOR UPDATE`, isolation levels | Document-level optimistic concurrency via `version` field or `findAndModify` |
| Analytics           | SQL `GROUP BY`, window functions, CTEs                     | Aggregation framework: `$group`, `$unwind`, `$bucket`, `$facet`     |
| Schema flexibility  | Poor — adding a column is a DDL operation                  | Excellent — `$jsonSchema` `oneOf` lets each exercise type carry its own fields |
| Horizontal scaling  | Read replicas + native partitioning; sharding needs Citus/etc. | Built-in sharding by shard key; replica sets are first-class |
| Suitability for IronCore | Money, bookings, time-overlap invariants         | Workout logs (variable shape), trainer notes (free text + tags), progress tracking over time |
| Hosting in Nigeria (NDPA 2023) | Mature managed offerings (RDS, Aurora, local cloud) | MongoDB Atlas has Lagos-region-equivalent deployment via Azure/Google/GCP Nigeria region |

## When the document model wins for IronCore

- **Workout logs** are the textbook case for MongoDB. A strength exercise has
  `sets/reps/weight_kg`, a cardio exercise has `distance_km/duration_min`, and a
  flexibility exercise has `duration_min/hold_sec`. In SQL we would need either
  three exercise tables (`strength_exercises`, `cardio_exercises`,
  `flexibility_exercises`) plus a parent `exercise` table with a discriminator
  column, or one wide table where two-thirds of the columns are NULL on every row.
  The MongoDB document stores the natural shape per exercise, validated by
  `$jsonSchema`'s `oneOf` branch — exactly the validation idiom the case study
  asks for.
- **Trainer notes** are open-ended: a note today might be "knee recovering, switch to
  low-impact", tomorrow "ready for HIIT". The set of tags grows over time. A SQL
  schema would need an `ENUM` migration for every new tag; MongoDB just stores the
  array.
- **Body measurements over time** are per-member time series; the set of measured
  fields varies (sometimes only weight is recorded, sometimes the full set). The
  document model allows sparse measurements without schema changes.

## When the SQL model wins for IronCore

- **Bookings + capacity** is a hard invariant enforced by triggers and exclusion
  constraints. Doing this in MongoDB would mean a "transaction that reads
  capacity, counts existing BOOKED, then inserts" — exactly the race the SQL side
  prevents with `FOR UPDATE` and advisory locks. MongoDB 4.0+ supports multi-document
  transactions, but the SQL tooling (triggers, `EXCLUDE USING gist`, `SERIAL` /
  `BIGSERIAL`, deferred constraints) is much stronger for this class of invariant.
- **Payments** must satisfy `reference UNIQUE` and `amount_naira > 0`. SQL CHECK
  + UNIQUE are simpler and cheaper than equivalent MongoDB validations.
- **Trainer scheduling** (no two overlapping sessions for the same trainer) is a
  classic SQL GiST exclusion — there is no equivalent in MongoDB.

## Honest summary

IronCore uses SQL where the schema is fixed and the invariants are temporal or
money-related, and uses MongoDB where the natural unit is a document with a
variable shape. Both stores are hosted in a Nigeria-resident deployment to comply
with NDPA 2023 (see P5).
