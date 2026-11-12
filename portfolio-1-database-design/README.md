# Portfolio 1 — Database Design & Modelling

**Case study:** IronCore Fitness — Nigerian gym chain (Abuja/Wuse, Abuja/Gwarinpa, Kano,
Kaduna, Lagos/Lekki). Members buy monthly / quarterly / annual plans, book group classes
with a trainer, check in, and join a waitlist when a class is full.

**Study sessions applied (see `docs/00_brief_summary.md`):**
Session 1 Introduction · Session 2 ER modelling · Session 3 Relational schema ·
Session 4 Normalisation (1NF/2NF/3NF/BCNF) · Session 5 Integrity constraints & triggers.

## Files

| File                | Purpose                                                        |
|---------------------|---------------------------------------------------------------|
| `schema.sql`        | 9 tables + 3 triggers + 2 views, all constraints              |
| `seed.sql`          | deterministic seed (5 branches, 10 trainers, 30 members)     |
| `generate_bulk.sql` | 6,000 members, 5,500+ memberships, 11,000+ class sessions, 60,000+ bookings |
| `constraint_tests.sql` | 7 tests that must fail (each builds its own data)          |
| `normalisation.md`  | 1NF / 2NF / 3NF explanation for the schema                    |
| `er_diagram.md`     | Mermaid ER diagram (renders on GitHub) + relational schema    |
| `run_p1.sh`         | runs all of the above in order                                |

## Codespaces commands

```bash
bash setup.sh                                                  # one-off, installs + starts PostgreSQL 16
bash portfolio-1-database-design/run_p1.sh                     # P1 end-to-end (~3-5 min on Codespaces)
```

## What to screenshot (drop into `portfolio-1-database-design/screenshots/`)

1. The end of `run_p1.sh` showing the bulk counts (members, memberships, sessions, bookings).
2. The 7 `PASS:` lines from `constraint_tests.sql` (each test must print `PASS:`).
3. The ER diagram rendered on GitHub (open `portfolio-1-database-design/er_diagram.md`
   on github.com — it auto-renders the mermaid block).
4. `\d ironcore.class_booking` and `\d ironcore.class_session` showing the exclusion
   constraints and triggers (run in `psql` against `ironcore`).

## Git commit

```bash
git add portfolio-1-database-design/ && \
  git commit -m "P1: schema, ER, 3NF, exclusion + trigger constraints, bulk generator (60k+ bookings), constraint tests"
```

## What this demonstrates

- ER design for ~9 related tables (Study Session 2).
- 3NF reasoning with explicit choice of which attribute lives on which table (Session 4).
- Advanced integrity enforcement using GiST exclusion constraints for time overlap
  (memberships, trainer sessions), and triggers for capacity + waitlist promotion (Session 5).
- A realistic Nigerian data context: ₦ prices, Yoruba/Hausa/Igbo names, branches in
  Abuja/Kano/Kaduna/Lagos, January busy season and evening peak hours.
- Self-contained tests that create their own data and ROLLBACK, so re-running never
  pollutes the bulk data.
