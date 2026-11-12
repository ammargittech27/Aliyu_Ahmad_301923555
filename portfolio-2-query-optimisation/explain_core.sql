-- Shared by explain_before.sql and explain_after.sql (same 6 queries, same data, only the indexes differ).
\set ON_ERROR_STOP on
SET search_path = ironcore, public;
SET timezone TO 'Africa/Lagos';
\set mid 1234
\echo '== Q1 EXPLAIN ANALYZE' :phase '=='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT b.name, s.class_session_id, ct.name, s.start_time, s.capacity, COUNT(bk.booking_id) FILTER (WHERE bk.status='BOOKED')
FROM class_session s JOIN branch b ON b.branch_id=s.branch_id JOIN class_type ct ON ct.class_type_id=s.class_type_id
LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id
WHERE s.start_time >= CURRENT_DATE AND s.start_time < CURRENT_DATE + 1
GROUP BY b.name, s.class_session_id, ct.name, s.start_time, s.capacity;
\echo '== Q2 EXPLAIN ANALYZE' :phase '=='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT ct.name, COUNT(DISTINCT s.class_session_id), SUM(s.capacity), COUNT(bk.booking_id) FILTER (WHERE bk.status IN ('BOOKED','ATTENDED'))
FROM class_type ct JOIN class_session s ON s.class_type_id=ct.class_type_id
LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id GROUP BY ct.name;
\echo '== Q3 EXPLAIN ANALYZE' :phase '=='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT EXTRACT(HOUR FROM s.start_time AT TIME ZONE 'Africa/Lagos'), COUNT(*), COUNT(bk.booking_id)
FROM class_session s LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id GROUP BY 1;
\echo '== Q4 EXPLAIN ANALYZE' :phase '=='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT m.member_id, m.first_name, m.last_name, ms.end_date FROM membership ms JOIN member m ON m.member_id=ms.member_id
WHERE ms.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7;
\echo '== Q5 EXPLAIN ANALYZE' :phase '=='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT t.first_name, COUNT(DISTINCT s.class_session_id), COUNT(bk.booking_id)
FROM trainer t JOIN class_session s ON s.trainer_id=t.trainer_id LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id
WHERE t.trainer_id=(SELECT MIN(trainer_id) FROM trainer) AND s.start_time >= now() - INTERVAL '90 days' GROUP BY t.first_name;
\echo '== Q6 EXPLAIN ANALYZE' :phase '=='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT bk.booking_id, s.start_time, ct.name, bk.status FROM class_booking bk
JOIN class_session s ON s.class_session_id=bk.class_session_id JOIN class_type ct ON ct.class_type_id=s.class_type_id
WHERE bk.member_id = :mid;
