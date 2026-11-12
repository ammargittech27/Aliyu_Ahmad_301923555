# Portfolio 4 — NoSQL & Advanced Data Models

**Case study:** IronCore Fitness — workout logs, trainer notes and body
measurements live in MongoDB; everything else stays in PostgreSQL. The two
stores are kept consistent at the entity-id level (member/branch/trainer ids
match).

**Study sessions applied:** Session 14 (NoSQL data models — document, key-value,
column, graph) · Session 15 (MongoDB & document validation — `$jsonSchema`,
`oneOf`/`anyOf`) · Session 16 (Aggregation framework & indexing).

## Files

| File                    | Purpose                                                          |
|-------------------------|------------------------------------------------------------------|
| `schema_validation.js`  | Creates `workouts`, `trainer_notes`, `body_measurements` with strict `$jsonSchema` validation. Workouts use **`oneOf`** (not if/then) to require the right fields per exercise type (strength = sets/reps/weight_kg · cardio = distance_km/duration_min · flexibility = duration_min/hold_sec). |
| `generate_data.js`     | Generates **40,000+ documents**: ~42,000 workouts, 2,000 trainer notes, 4,800 body measurements |
| `aggregations.js`      | 3+1 aggregations: most popular exercises; average progress per member; trainer notes per branch; bonus top exercise per branch |
| `create_index.js`      | Demonstrates **COLLSCAN → IXSCAN** by creating a compound index `(member_id, date)` |
| `sql_vs_nosql.md`      | Honest comparison of where each piece of IronCore lives and why |
| `run_p4.sh`            | runs the whole pipeline                                            |

## Codespaces commands

```bash
bash setup.sh                                  # installs MongoDB 8 (one-off)
bash portfolio-4-nosql/run_p4.sh                # P4 end-to-end
```

## What to screenshot

1. The end of `run_p4.sh` showing the document counts (`workouts`, `trainer_notes`,
   `body_measurements`) — total > 40,000.
2. The COLLSCAN `winningPlan` from the "before" `explain()` in step 1 of
   `create_index.js`.
3. The IXSCAN `winningPlan` from the "after" `explain()` in step 3.
4. The "STEP 4 — Summary comparison" block from `create_index.js` showing
   `totalDocsExamined` and `executionTimeMillis` for both runs.
5. The output of `aggregations.js` (top 15 most popular exercises, per-member weight
   delta, notes per branch).
6. **Schema rejection test** — try to insert a strength exercise without
   `weight_kg`; MongoDB should reject it:
   ```bash
   mongosh --quiet --eval '
     db = db.getSiblingDB("ironcore_gym");
     try {
       db.workouts.insertOne({
         workout_id: NumberLong(999999),
         member_id: NumberLong(1), branch_id: 1, trainer_id: NumberLong(1),
         date: new Date(), type: "strength",
         exercises: [{ name: "Bad lift", type: "strength", sets: 3, reps: 5 }],
         created_at: new Date()
       });
       print("ERROR — should have been rejected");
     } catch (e) {
       print("OK — rejected: " + e.message.slice(0, 200));
     }'
   ```

## Index demo — comparison table (fill with real numbers)

> Run `create_index.js` and copy the summary block into the table below. Replace
> the numbers printed in STEP 4 of `p4_output.log` (they are also copied into `my_results.txt`).

| | COLLSCAN (before) | IXSCAN (after) |
|---|---|---|
| winningPlan stage | see `p4_output.log` STEP 4 | see `p4_output.log` STEP 4 |
| totalDocsExamined | see `p4_output.log` STEP 4 | see `p4_output.log` STEP 4 |
| executionTimeMillis | see `p4_output.log` STEP 4 | see `p4_output.log` STEP 4 |
| index used              | (none)                  | idx_member_date |
| What changed            | COLLSCAN scans all ~42,000 workout documents | IXSCAN seeks directly to the 10 documents for `member_id = 7` and the index is already sorted by `date desc` |

## Git commit

```bash
git add portfolio-4-nosql/ && \
  git commit -m "P4: MongoDB workout logs + trainer notes + body measurements with \$jsonSchema oneOf validation, 40k+ docs, aggregations, COLLSCAN -> IXSCAN demo"
```

## What this demonstrates

- Document model for **naturally-variable-shape** data (exercise fields depend on
  exercise type) — implemented with `$jsonSchema` `oneOf`, the validation idiom
  required by the brief.
- Bulk data generation (40k+ documents) in a single mongosh script, no CSV/JSON files.
- Aggregation framework usage (`$unwind`, `$group`, `$first`, `$last`, `$addToSet`,
  `$slice`, `$project`) — three required aggregations plus a bonus per-branch.
- Index design: a compound `(member_id, date)` index answers "find this member's
  latest workouts" with a single IXSCAN — no in-memory sort needed because the index
  is already sorted.
- Honest comparison (see `sql_vs_nosql.md`) of which IronCore data belongs where and
  why, grounded in the actual schema choices made in P1–P3.
