-- portfolio-3 race fixture: ONE dedicated class (capacity 20, 10 days ahead, own trainer) that every demo resets.
\set ON_ERROR_STOP on
SET search_path TO ironcore, public;
SET timezone TO 'Africa/Lagos';

CREATE OR REPLACE FUNCTION ironcore.reset_race_session(n_booked INT DEFAULT 19) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE s_id BIGINT; t_id BIGINT; b_id INT; c_id INT; day DATE := CURRENT_DATE + 10;
        ts TIMESTAMPTZ := ((CURRENT_DATE + 10) + TIME '04:00') AT TIME ZONE 'Africa/Lagos';
BEGIN
    SELECT branch_id INTO b_id FROM branch ORDER BY 1 LIMIT 1;
    SELECT class_type_id INTO c_id FROM class_type ORDER BY 1 LIMIT 1;
    SELECT trainer_id INTO t_id FROM trainer WHERE email = 'race.coach@ironcore.ng';
    IF t_id IS NULL THEN
        INSERT INTO trainer (first_name, last_name, email, specialization, branch_id)
        VALUES ('Race','Coach','race.coach@ironcore.ng','HIIT',b_id) RETURNING trainer_id INTO t_id;
    END IF;
    SELECT class_session_id INTO s_id FROM class_session WHERE trainer_id = t_id ORDER BY class_session_id LIMIT 1;
    IF s_id IS NULL THEN
        INSERT INTO class_session (branch_id, class_type_id, trainer_id, start_time, end_time, capacity)
        VALUES (b_id, c_id, t_id, ts, ts + INTERVAL '60 minutes', 20) RETURNING class_session_id INTO s_id;
    ELSE
        UPDATE class_session SET start_time = ts, end_time = ts + INTERVAL '60 minutes', capacity = 20 WHERE class_session_id = s_id;
    END IF;
    DELETE FROM class_booking WHERE class_session_id = s_id;
    -- members whose membership covers the class day, in a fixed order
    INSERT INTO class_booking (class_session_id, member_id, status)
    SELECT s_id, member_id, 'BOOKED' FROM (
        SELECT DISTINCT ms.member_id FROM membership ms WHERE ms.start_date <= day AND ms.end_date >= day
        ORDER BY ms.member_id LIMIT n_booked) q;
    RETURN s_id;
END $$;

\echo 'Race fixture ready:'
SELECT ironcore.reset_race_session(19) AS race_session_id;
SELECT s.capacity, COUNT(*) FILTER (WHERE b.status='BOOKED') AS booked
FROM class_session s LEFT JOIN class_booking b USING (class_session_id)
WHERE s.class_session_id = (SELECT class_session_id FROM class_session cs JOIN trainer t USING (trainer_id) WHERE t.email='race.coach@ironcore.ng')
GROUP BY s.capacity;
