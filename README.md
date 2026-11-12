# IronCore Fitness — MIT 8103 Advanced Database Systems Portfolio

**Student:** Ahmad Aliyu Bello
**Matric:** 2026/A/MIT/0537
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems (First Semester CA, Sept 2026 cohort)
**GitHub repository:** [GitHub link]

---

## Case study

**IronCore Fitness** is a simulated Nigerian gym chain with five branches:

| City   | Branch           |
|--------|------------------|
| Abuja  | Wuse             |
| Abuja  | Gwarinpa         |
| Kano   | Kano City        |
| Kaduna | Kaduna City      |
| Lagos  | Lekki            |

Members buy **monthly / quarterly / annual** plans, book **group classes** (spinning, HIIT,
yoga, boxing, aerobics) led by a trainer, **check in** at the door, and join a **waitlist**
when a class is full. When a booked member cancels, the first person on the waitlist is
promoted automatically. Prices, names and dates are Nigerian (₦, Yoruba/Hausa/Igbo names,
Lagos/Abuja/Kano/Kaduna context).

---

## Repository structure

```
advanced-database-portfolio/
├── README.md                          # this file
├── setup.sh                           # installs + starts PostgreSQL 16 and MongoDB 8
├── docs/
│   ├── 00_brief_summary.md            # CA summary + study-session mapping
│   └── REFERENCES.md
├── portfolio-1-database-design/       # 7 marks  — ER, 3NF, constraints, bulk data, tests
├── portfolio-2-query-optimisation/    # 7 marks  — queries + EXPLAIN ANALYZE + indexes
├── portfolio-3-transactions-concurrency/ # 7 marks — book/cancel txns, race, isolation, deadlock
├── portfolio-4-nosql/                  # 7 marks  — MongoDB workout logs + trainer notes
└── portfolio-5-distributed-cloud/      # 6 marks  — partitioning + replica + cloud/NDPA 2023
```

A 2–3 page documentation PDF (`Bello_Ahmad_2026-A-MIT-0537_Documentation.pdf`) will be
produced **after** the student runs everything, using only the real results captured by the
the output files the student's own Codespace run saves (`my_results.txt` and the per-portfolio `pN_output.log`). It is not part of this zip.

---

## Quick start (Codespaces / Ubuntu 24.04)

```bash
# 1. Install + start PostgreSQL 16 and MongoDB 8
bash setup.sh

# 2. Run each portfolio in order (each is idempotent — re-running rebuilds from scratch)
bash portfolio-1-database-design/run_p1.sh     # builds schema, seeds, generates 5k memberships + 50k bookings
bash portfolio-2-query-optimisation/run_p2.sh  # runs queries, EXPLAIN ANALYZE before/after indexes
bash portfolio-3-transactions-concurrency/run_p3.sh   # builds tx functions + race/isolation/deadlock demos
bash portfolio-4-nosql/run_p4.sh               # loads 40k+ MongoDB docs, runs aggregations + index demo
bash portfolio-5-distributed-cloud/run_p5.sh   # partitions class_booking by month + sets up streaming replica
```

Connection rule used everywhere in this repo: connect over the **Unix socket**
(`-h /var/run/postgresql`), not TCP. TCP logins require a password; the Unix socket
authenticates by OS user (`postgres`) via `trust` lines added at the **top** of `pg_hba.conf`.

For MongoDB, every mongosh script uses `db = db.getSiblingDB("ironcore_gym")` rather than
the `use <db>;` shell syntax.

---

## Honesty / AI-use declaration

- No EXPLAIN plan, timing, screenshot or query output has been fabricated. Where real
  results are expected, the real numbers come from `my_results.txt` after the run.
- Bulk data is generated inside SQL / mongosh scripts (`generate_series`, loops). No large
  CSV / JSON data files are shipped.
- All dates are computed relative to `CURRENT_DATE` (2 years of history + the next 14 days
  of class sessions), so the repo never expires.
- AI assistance: the scripts, schema and documentation were drafted with the help of an AI
  assistant (model used for: scaffolding, drafting SQL/JS, writing the ER diagram in
  Mermaid, structuring the README files). The student has reviewed, corrected and tested
  each script and is responsible for the contents. See `docs/REFERENCES.md`.

---

## Suggested progressive git commits

```bash
git init && git add docs && git commit -m "docs: CA brief + study-session mapping + references"
git add setup.sh README.md portfolio-1-database-design && git commit -m "P1: schema, 3NF, constraints, bulk data, tests"
git add portfolio-2-query-optimisation && git commit -m "P2: queries + EXPLAIN ANALYZE before/after indexes"
git add portfolio-3-transactions-concurrency && git commit -m "P3: book/cancel txns, race, isolation, deadlock"
git add portfolio-4-nosql && git commit -m "P4: MongoDB workout logs + trainer notes + aggregations + index"
git add portfolio-5-distributed-cloud && git commit -m "P5: partitioning + streaming replica + NDPA 2023 cloud design"
```
