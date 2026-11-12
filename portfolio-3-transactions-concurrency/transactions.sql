-- portfolio-3-transactions-concurrency/transactions.sql
-- Stored procedures for the two main business transactions:
--   * ironcore.book_class(p_member_id, p_class_session_id)  -> book or waitlist
--   * ironcore.cancel_booking(p_member_id, p_class_session_id) -> cancel + promote
-- Plus a small COMMIT/ROLLBACK example at the bottom.
-- Idempotent: CREATE OR REPLACE.
\set ON_ERROR_STOP on
SET search_path = ironcore, public;
SET timezone TO 'Africa/Lagos';

-- ===========================================================================
-- book_class()
-- ===========================================================================
CREATE OR REPLACE FUNCTION ironcore.book_class(
    p_member_id       BIGINT,
    p_class_session_id BIGINT
) RETURNS TABLE(out_booking_id BIGINT, out_status TEXT, out_waitlist_position INT)
LANGUAGE plpgsql AS $$
DECLARE
    cap             INT;
    current_booked  INT;
    next_pos        INT;
    class_day       DATE;
    active          BOOLEAN;
    new_booking_id  BIGINT;
    chosen_status   TEXT;
    chosen_pos      INT;
BEGIN
    -- Step 1: check the class exists; FOR UPDATE to lock the row.
    -- Locking class_session serialises concurrent bookers for this class.
    SELECT  capacity,
            (start_time AT TIME ZONE 'Africa/Lagos')::date
       INTO cap, class_day
    FROM    class_session
    WHERE   class_session_id = p_class_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'class_session_id % does not exist', p_class_session_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Step 2: check active membership on the class day.
    SELECT EXISTS (
        SELECT 1 FROM membership
        WHERE member_id   = p_member_id
          AND start_date <= class_day
          AND end_date   >= class_day
    ) INTO active;

    IF NOT active THEN
        RAISE EXCEPTION 'Member % has no active membership on % for class %',
            p_member_id, class_day, p_class_session_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- Step 3: count currently BOOKED rows for this class.
    SELECT COUNT(*) INTO current_booked
    FROM   class_booking
    WHERE  class_session_id = p_class_session_id
      AND  status = 'BOOKED';

    IF current_booked >= cap THEN
        SELECT COALESCE(MAX(waitlist_position), 0) + 1 INTO next_pos
        FROM   class_booking
        WHERE  class_session_id = p_class_session_id
          AND  status = 'WAITLISTED';
        chosen_status := 'WAITLISTED';
        chosen_pos    := next_pos;
    ELSE
        chosen_status := 'BOOKED';
        chosen_pos    := NULL;
    END IF;

    -- Step 4: INSERT. Use a nested block so we can return a tidy error on UNIQUE violations.
    BEGIN
        INSERT INTO class_booking (class_session_id, member_id, status, waitlist_position)
        VALUES (p_class_session_id, p_member_id, chosen_status, chosen_pos)
        RETURNING booking_id INTO new_booking_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'Member % already has a booking for class %',
                p_member_id, p_class_session_id
                USING ERRCODE = 'unique_violation';
    END;

    RETURN QUERY SELECT new_booking_id, chosen_status, chosen_pos;
END;
$$;

-- ===========================================================================
-- cancel_booking()
-- ===========================================================================
CREATE OR REPLACE FUNCTION ironcore.cancel_booking(
    p_member_id        BIGINT,
    p_class_session_id BIGINT
) RETURNS TABLE(out_booking_id BIGINT, out_promoted_booking_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
    target_booking_id BIGINT;
    target_status     TEXT;
    next_booking_id   BIGINT;
    next_pos          INT;
BEGIN
    -- Step 1: find the member's booking for this class, lock the row.
    SELECT booking_id, status
      INTO target_booking_id, target_status
    FROM   class_booking
    WHERE  class_session_id = p_class_session_id
      AND  member_id        = p_member_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No booking for member % in class %',
            p_member_id, p_class_session_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF target_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking already CANCELLED — no-op.';
        RETURN QUERY SELECT target_booking_id, NULL::bigint;
        RETURN;
    END IF;

    -- Step 2: cancel the booking (the AFTER UPDATE trigger will promote the waitlist).
    UPDATE class_booking
       SET status = 'CANCELLED', waitlist_position = NULL
     WHERE booking_id = target_booking_id;

    -- Step 3: read what the trigger promoted, if anything.
    SELECT b.booking_id INTO next_booking_id
    FROM   class_booking b
    WHERE  b.class_session_id = p_class_session_id
      AND  b.status = 'BOOKED'
      AND  b.member_id <> p_member_id
    ORDER BY b.booked_at DESC
    LIMIT 1;

    RETURN QUERY SELECT target_booking_id, next_booking_id;
END;
$$;

-- ===========================================================================
-- A COMMIT / ROLLBACK example using the two procedures
-- ===========================================================================
\echo ''
\echo '== COMMIT example: book a real member into a class today =='
DO $$
DECLARE bid BIGINT; st TEXT; pos INT; chosen_m BIGINT; chosen_s BIGINT;
BEGIN
    SELECT ms.member_id, cs.class_session_id INTO chosen_m, chosen_s
    FROM   membership ms
    JOIN   class_session cs ON (cs.start_time AT TIME ZONE 'Africa/Lagos')::date = CURRENT_DATE
    WHERE  ms.start_date <= CURRENT_DATE AND ms.end_date >= CURRENT_DATE
      AND  NOT EXISTS (SELECT 1 FROM class_booking b WHERE b.class_session_id = cs.class_session_id AND b.member_id = ms.member_id)
    ORDER BY cs.class_session_id, ms.member_id LIMIT 1;
    IF chosen_m IS NULL THEN RAISE EXCEPTION 'no eligible member/class for the COMMIT demo'; END IF;
    SELECT * INTO bid, st, pos FROM ironcore.book_class(chosen_m, chosen_s);
    RAISE NOTICE 'book_class OK: member % class % -> booking_id=% status=%', chosen_m, chosen_s, bid, st;
END $$;

\echo ''
\echo '== ROLLBACK example 1: undo a whole transaction =='
SELECT count(*) AS members_before FROM member;
BEGIN;
INSERT INTO member (first_name, last_name, email) VALUES ('Rollback','Demo','rollback.demo@example.com');
SELECT count(*) AS members_inside_tx FROM member;
ROLLBACK;
SELECT count(*) AS members_after_rollback FROM member;

\echo ''
\echo '== ROLLBACK example 2: book_class refuses a member with no membership =='
BEGIN;
DO $$
DECLARE m BIGINT; s BIGINT;
BEGIN
    INSERT INTO member (first_name, last_name, email) VALUES ('NoPlan','Member','noplan@example.com') RETURNING member_id INTO m;
    SELECT class_session_id INTO s FROM class_session WHERE start_time > now() ORDER BY start_time LIMIT 1;
    BEGIN
        PERFORM * FROM ironcore.book_class(m, s);
        RAISE EXCEPTION 'FAIL: booking without membership was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: rejected - %', SQLERRM;
    END;
END $$;
ROLLBACK;
\echo 'ROLLED BACK - no rows kept.'
