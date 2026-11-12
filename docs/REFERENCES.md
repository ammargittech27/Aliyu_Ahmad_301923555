# References

## Course materials
1. Miva Open University, *MIT 8103 Advanced Database Systems — Course Notes* (Sept 2026
   cohort). Supplied as `Edited - MIT8103 Advanced Database Systems.pdf` (154-page scanned
   hand-out). Sessions referenced in `00_brief_summary.md` follow the standard Miva MIT 8103
   study-session titles.
2. Miva Open University, *MIT 8103 Advanced Database Systems — Continuous Assessment Brief*
   (Sept 2026 cohort). Supplied as
   `mit-8103-advanced-database-systems-ca-september-cohort-2026.pdf`.

## Software documentation
3. PostgreSQL Global Development Group, *PostgreSQL 16 Documentation*. Chapters used:
   *Constraints* (exclusion constraints with `btree_gist`), *Table Partitioning*, *Row
   Security Policies*, *Triggers*, *Explicit Locking* (`FOR UPDATE`, advisory locks),
   *Transaction Isolation*, *Streaming Replication*, *High Availability*. <https://www.postgresql.org/docs/16/>.
4. MongoDB Inc., *MongoDB 8.0 Manual*. Sections used: *Schema Validation* (`$jsonSchema`,
   `oneOf`/`anyOf`), *Aggregation Framework*, *Indexes*, *Sharding*. <https://www.mongodb.com/docs/manual/>.

## Standards & regulation
5. Federal Government of Nigeria, *Nigeria Data Protection Act, 2023 (NDPA 2023)* — establishes
   the Nigeria Data Protection Commission; governs processing and storage of personal data
   of Nigerian residents, including cross-border transfer and residency requirements.
   <https://ndpc.gov.ng/wp-content/uploads/2023/06/Nigeria-Data-Protection-Act-2023.pdf>.

## Concept references (textbooks used during drafting)
6. Elmasri, R. & Navathe, S. B., *Fundamentals of Database Systems*, 7th ed., Pearson, 2015
   — ER modelling, normalisation, transaction & recovery chapters.
7. Kleppmann, M., *Designing Data-Intensive Applications*, O'Reilly, 2017 — CAP, replication,
   partitioning, consistency models.
8. Connolly, T. & Begg, C., *Database Systems: A Practical Approach to Design,
   Implementation, and Management*, 6th ed., Pearson, 2014.

## AI-use declaration (also in top-level README.md)
- **Tool used:** an AI coding assistant based on the GLM model (Z.ai).
- **Used for:** scaffolding the repository, drafting the SQL schema, trigger functions,
  transaction procedures, MongoDB schema validation and aggregation pipelines, the Mermaid
  ER diagram, the README files and the bulk-data generators.
- **Reviewed/corrected by the student:** every script is re-read before running; the student
  writes the documentation from the real results captured in Codespaces (`my_results.txt`)
  and writes the 2–3 page documentation from those real results only. The student signs off
  on each portfolio before committing to GitHub.
