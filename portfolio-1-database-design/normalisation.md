# Normalisation notes (3NF) — IronCore Fitness

## Entities and keys

| Table            | Primary key         | Candidate keys                                |
|------------------|---------------------|-----------------------------------------------|
| branch           | branch_id           | (name, area)                                  |
| member           | member_id           | email                                         |
| plan             | plan_id             | name                                          |
| membership       | membership_id       | (member_id, start_date) — provided no overlap |
| trainer          | trainer_id          | email                                         |
| class_type       | class_type_id       | name                                          |
| class_session    | class_session_id    | (branch_id, trainer_id, start_time)           |
| class_booking    | booking_id          | (class_session_id, member_id)                 |
| payment          | payment_id          | reference                                     |

## 1NF — atomic values

Every column in every table holds a single scalar value. Names are stored as
`first_name` + `last_name` (not one column). Addresses are a single text field because
the system does not query on house number / street separately. `class_booking.status` is
a single CHECK-constrained string, not a comma-separated list. `class_booking` does not
hold a set of members — each member-class pairing is one row. The diagram is therefore
already in 1NF.

## 2NF — no partial dependencies (only applies to composite-key tables)

The only composite-keyed table is `class_booking`, with the surrogate `booking_id` as the
real primary key and the `UNIQUE (class_session_id, member_id)` as a candidate key.
Every non-key column (`status`, `waitlist_position`, `booked_at`) depends on the whole
key (member + class) — none depends on `class_session_id` alone or `member_id` alone.
So `class_booking` is in 2NF. All other tables have single-column surrogate keys, so 2NF
is automatic.

## 3NF — no transitive dependencies

Each non-key column depends *only* on the primary key of its own table, never on another
non-key column. Concretely:

- `member.city` is **not** stored — city lives on `branch`, so a member has no transitive
  `member → branch → city` dependency.
- `class_session.capacity` belongs to the *session* (a one-off schedule), not to
  `class_type` (whose `default_duration_min` is a separate attribute of the type). Capacity
  is a property of the scheduled session and the room it is in, so 3NF is preserved.
- `payment.amount_naira` is stored on `payment`, not derived via `membership → plan →
  price_naira`, because payments can deviate from the list price (discounts, promos,
  late-payment). This avoids a transitive `payment → membership → plan → price`.
- `trainer.specialization` lives on `trainer`, not on `branch` or `class_type`, because
  a trainer's specialization is independent of where they teach or what they are teaching
  today.
- `membership` does not store `plan_name` or `price_naira`; it references `plan_id`, so
  the schema has no transitive dependency from `membership → plan → price`.

## Design choices worth defending

- **Exclusion constraints (GiST)** are used for time-overlap rules (memberships, trainer
  sessions). They cannot be enforced by simple UNIQUE or CHECK constraints; btree_gist
  supports `daterange && daterange` and `tstzrange && tstzrange`.
- **Trigger-based capacity rule.** "Booked places never exceed capacity" is data-dependent
  (it depends on the *current* count of BOOKED rows for that session) and so cannot be a
  static constraint. A BEFORE INSERT trigger either assigns BOOKED or moves the row to
  WAITLISTED with the next position.
- **Trigger-based promotion.** When a BOOKED row is cancelled, the first WAITLISTED row is
  promoted in the same AFTER UPDATE trigger; the rest of the waitlist is shifted down by
  one position. This keeps waitlist positions contiguous.
- **Surrogate keys** (`BIGSERIAL`) are used everywhere; natural keys are enforced as
  additional UNIQUE constraints (`email`, `branch(name, area)`, `plan.name`,
  `payment.reference`).
- **`waitlist_position` is nullable** and CHECK-constrained to be present only when
  `status = 'WAITLISTED'`. This avoids the ambiguity of "0 means BOOKED".
