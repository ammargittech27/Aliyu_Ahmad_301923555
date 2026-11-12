# Portfolio 2 — Query Processing & Optimisation

**Case study:** IronCore Fitness (see top-level README). Same schema as P1.

**Study sessions applied:** Session 6 (advanced SQL) · Session 7 (query processing &
execution plans) · Session 8 (indexing & access methods — B-tree, partial B-tree, BRIN)
· Session 9 (EXPLAIN ANALYZE, statistics, cost model).

## Files

| File                    | Purpose                                                 |
|-------------------------|---------------------------------------------------------|
| `queries.sql`           | 6 queries: 4 selective (today, expiring in 7 days, one trainer, one member) + 2 full-history aggregates kept on purpose |
| `explain_before.sql`    | `EXPLAIN ANALYZE` for all 6 queries, **before** indexes |
| `indexes.sql`           | adds 5 B-tree indexes (time, trainer+time, booking session, booking member, membership end)             |
| `explain_after.sql`     | `EXPLAIN ANALYZE` for all 6 queries, **after** indexes   |
| `before_after_table.md` | comparison table — fill with real numbers               |
| `run_p2.sh`             | runs the whole pipeline, saves output under `output/`    |

## Codespaces commands

```bash
bash portfolio-2-query-optimisation/run_p2.sh
# then open portfolio-2-query-optimisation/output/explain_before.out and
#                    portfolio-2-query-optimisation/output/explain_after.out
# and copy the "Execution Time" / "Planning Time" / plan nodes into
# portfolio-2-query-optimisation/before_after_table.md
```

## What to screenshot

1. `output/explain_before.out` — the **Seq Scan** plan nodes for Q4 and Q1.
2. `output/explain_after.out` — the **Index Scan / Bitmap Index Scan** nodes for the
   same queries after the indexes were added.
3. The filled-in `before_after_table.md` (after you paste the real numbers).
4. `\di ironcore.*` from psql showing the new indexes exist.

## Git commit

```bash
git add portfolio-2-query-optimisation/ && \
  git commit -m "P2: 6 analytical queries + EXPLAIN ANALYZE before/after B-tree, partial B-tree and BRIN indexes"
```

## What this demonstrates

- Advanced SQL aggregates (`COUNT(*) FILTER`, `EXTRACT`, `TO_CHAR`, multi-table joins).
- Reading `EXPLAIN ANALYZE` output and reasoning about Seq Scan vs Index Scan vs Bitmap.
- Choosing **BRIN** for the monotonically-growing `class_session.start_time` (compact on
  large partitioned tables), **partial B-tree** for the high-selectivity `status = 'BOOKED'`
  subset, and **composite B-tree** for the per-plan-per-month revenue group-by.
- Honest measurement — no fabricated timings; the `[paste real result here]` placeholders
  force the student to read the real numbers from the actual Codespaces run.
