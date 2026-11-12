-- BEFORE the P2 indexes (run_p2.sh has dropped every secondary index and run ANALYZE).
\set phase BEFORE
\i explain_core.sql
