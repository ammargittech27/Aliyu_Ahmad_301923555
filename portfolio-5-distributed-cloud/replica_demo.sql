-- portfolio-5-distributed-cloud/replica_demo.sql — ONE script that switches servers itself.
-- primary = /var/run/postgresql port 5432, replica = port 5433. Real output, nothing typed in.
\set ON_ERROR_STOP off
\pset pager off
\connect -reuse-previous=off ironcore postgres /var/run/postgresql 5432
SET search_path TO ironcore, public;
SET timezone TO 'Africa/Lagos';

\echo '== 1. Who is who =='
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica, 'PRIMARY' AS role;

-- pick a future class with free seats and a member with an active membership that day (not yet booked)
SELECT v.class_session_id AS demo_session_id
FROM v_session_booking_count v JOIN class_session s USING (class_session_id)
WHERE s.start_time > now() AND v.booked < v.capacity - 3 ORDER BY s.start_time, s.class_session_id LIMIT 1 \gset
SELECT ms.member_id AS demo_member_id
FROM membership ms JOIN class_session s ON s.class_session_id = :demo_session_id
WHERE ms.start_date <= (s.start_time AT TIME ZONE 'Africa/Lagos')::date AND ms.end_date >= (s.start_time AT TIME ZONE 'Africa/Lagos')::date
  AND NOT EXISTS (SELECT 1 FROM class_booking b WHERE b.class_session_id = s.class_session_id AND b.member_id = ms.member_id)
ORDER BY ms.member_id LIMIT 1 \gset
SELECT (start_time AT TIME ZONE 'Africa/Lagos')::date AS demo_date FROM class_session WHERE class_session_id = :demo_session_id \gset
\echo 'demo class_session_id =' :demo_session_id ' demo member_id =' :demo_member_id ' class_date =' :demo_date
SELECT COUNT(*) AS bookings_on_primary_before FROM class_booking;
SELECT COUNT(*) AS demo_rows_before FROM class_booking WHERE class_session_id = :demo_session_id AND member_id = :demo_member_id;

\connect -reuse-previous=off ironcore postgres /var/run/postgresql 5433
SET search_path TO ironcore, public;
\echo ''
\echo '== 2. Switched to the REPLICA =='
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica, 'REPLICA' AS role;
SELECT COUNT(*) AS bookings_on_replica_before FROM class_booking;
\echo '== 3. A write on the replica must be rejected (read-only) =='
INSERT INTO class_booking (class_session_id, member_id, class_date, status) VALUES (:demo_session_id, :demo_member_id, :'demo_date', 'BOOKED');

\connect -reuse-previous=off ironcore postgres /var/run/postgresql 5432
SET search_path TO ironcore, public;
\echo ''
\echo '== 4. Back on the PRIMARY: the same insert is accepted =='
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica;
INSERT INTO class_booking (class_session_id, member_id, class_date, status) VALUES (:demo_session_id, :demo_member_id, :'demo_date', 'BOOKED');
SELECT COUNT(*) AS bookings_on_primary_after FROM class_booking;
\! sleep 1

\connect -reuse-previous=off ironcore postgres /var/run/postgresql 5433
SET search_path TO ironcore, public;
\echo ''
\echo '== 5. The row has streamed to the REPLICA =='
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica;
SELECT COUNT(*) AS bookings_on_replica_after FROM class_booking;
SELECT COUNT(*) AS demo_row_on_replica FROM class_booking WHERE class_session_id = :demo_session_id AND member_id = :demo_member_id;
SELECT pg_last_wal_receive_lsn() AS received_lsn, pg_last_wal_replay_lsn() AS replayed_lsn,
       pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_gap_bytes;

\connect -reuse-previous=off ironcore postgres /var/run/postgresql 5432
\echo ''
\echo '== 6. pg_stat_replication on the PRIMARY =='
SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication;
