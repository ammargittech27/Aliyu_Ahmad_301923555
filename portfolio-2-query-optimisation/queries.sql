-- portfolio-2-query-optimisation/queries.sql
-- 6 analytical queries. Q1, Q4, Q5, Q6 are SELECTIVE (a day, a week, one trainer, one member):
-- indexes should help them. Q2 and Q3 aggregate the WHOLE history on purpose: an index cannot
-- help a query that must read every row, and the report says so honestly.
\set ON_ERROR_STOP on
SET search_path = ironcore, public;
SET timezone TO 'Africa/Lagos';
\set mid 1234

\echo '== Q1: free places in TODAY''s classes (selective: one day) =='
SELECT b.name AS branch, s.class_session_id, ct.name AS class_type, s.start_time, s.capacity,
       s.capacity - COUNT(bk.booking_id) FILTER (WHERE bk.status='BOOKED') AS free_places
FROM class_session s
JOIN branch b ON b.branch_id=s.branch_id
JOIN class_type ct ON ct.class_type_id=s.class_type_id
LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id
WHERE s.start_time >= CURRENT_DATE AND s.start_time < CURRENT_DATE + 1
GROUP BY b.name, s.class_session_id, ct.name, s.start_time, s.capacity
ORDER BY b.name, s.start_time LIMIT 10;

\echo '== Q2: fill rate per class type (FULL history, no index can help) =='
SELECT ct.name, COUNT(DISTINCT s.class_session_id) AS sessions, SUM(s.capacity) AS capacity,
       COUNT(bk.booking_id) FILTER (WHERE bk.status IN ('BOOKED','ATTENDED')) AS filled
FROM class_type ct JOIN class_session s ON s.class_type_id=ct.class_type_id
LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id
GROUP BY ct.name ORDER BY filled DESC;

\echo '== Q3: busiest hours (FULL history, no index can help) =='
SELECT EXTRACT(HOUR FROM s.start_time AT TIME ZONE 'Africa/Lagos') AS hour, COUNT(*) AS sessions, COUNT(bk.booking_id) AS bookings
FROM class_session s LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id
GROUP BY 1 ORDER BY bookings DESC;

\echo '== Q4: memberships expiring in the next 7 days (selective) =='
SELECT m.member_id, m.first_name, m.last_name, ms.end_date
FROM membership ms JOIN member m ON m.member_id=ms.member_id
WHERE ms.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY ms.end_date LIMIT 10;

\echo '== Q5: one trainer''s workload in the last 90 days (selective) =='
SELECT t.first_name, t.last_name, COUNT(DISTINCT s.class_session_id) AS sessions, COUNT(bk.booking_id) AS bookings
FROM trainer t JOIN class_session s ON s.trainer_id=t.trainer_id
LEFT JOIN class_booking bk ON bk.class_session_id=s.class_session_id
WHERE t.trainer_id = (SELECT MIN(trainer_id) FROM trainer) AND s.start_time >= now() - INTERVAL '90 days'
GROUP BY t.first_name, t.last_name;

\echo '== Q6: booking history of ONE member (selective) =='
SELECT bk.booking_id, s.start_time, ct.name, bk.status
FROM class_booking bk JOIN class_session s ON s.class_session_id=bk.class_session_id
JOIN class_type ct ON ct.class_type_id=s.class_type_id
WHERE bk.member_id = :mid ORDER BY s.start_time DESC LIMIT 10;
