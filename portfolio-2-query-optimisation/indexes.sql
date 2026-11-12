-- portfolio-2-query-optimisation/indexes.sql — the 5 indexes added for P2.
\set ON_ERROR_STOP on
SET search_path = ironcore, public;
CREATE INDEX IF NOT EXISTS p2_session_start      ON class_session (start_time);                  -- Q1, Q5 range on time
CREATE INDEX IF NOT EXISTS p2_session_trainer_ts ON class_session (trainer_id, start_time);      -- Q5 one trainer + time
CREATE INDEX IF NOT EXISTS p2_booking_session    ON class_booking (class_session_id, status);    -- Q1 join to bookings
CREATE INDEX IF NOT EXISTS p2_booking_member     ON class_booking (member_id);                   -- Q6 one member
CREATE INDEX IF NOT EXISTS p2_membership_end     ON membership (end_date);                       -- Q4 expiring soon
\echo 'P2 indexes created: p2_session_start, p2_session_trainer_ts, p2_booking_session, p2_booking_member, p2_membership_end'
