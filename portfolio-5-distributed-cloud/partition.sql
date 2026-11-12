-- portfolio-5-distributed-cloud/partition.sql
-- Rebuild class_booking as a monthly RANGE-partitioned table (partition key class_date), keep the
-- three triggers, and compare a one-month query against an unpartitioned copy. Re-runnable: if the
-- table is already partitioned the rebuild is skipped.
\set ON_ERROR_STOP on
SET search_path = ironcore, public;
SET timezone TO 'Africa/Lagos';

SELECT EXISTS (SELECT 1 FROM pg_class WHERE relname='class_booking' AND relnamespace='ironcore'::regnamespace AND relkind='p') AS already_partitioned \gset

\if :already_partitioned
\echo '== class_booking is already partitioned - skipping the rebuild =='
\else
\echo '== Rebuilding class_booking as a RANGE-partitioned table =='
CREATE TABLE _booking_flat AS
SELECT b.booking_id, b.class_session_id, b.member_id, (s.start_time AT TIME ZONE 'Africa/Lagos')::date AS class_date,
       b.status, b.waitlist_position, b.booked_at
FROM class_booking b JOIN class_session s ON s.class_session_id = b.class_session_id;

DROP TABLE class_booking CASCADE;   -- also drops its triggers and the v_session_booking_count view

CREATE TABLE class_booking (
    booking_id          BIGSERIAL,
    class_session_id    BIGINT  NOT NULL REFERENCES class_session(class_session_id),
    member_id           BIGINT  NOT NULL REFERENCES member(member_id),
    class_date          DATE    NOT NULL,
    status              TEXT    NOT NULL CHECK (status IN ('BOOKED','WAITLISTED','CANCELLED','ATTENDED')),
    waitlist_position   INT,
    booked_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- a UNIQUE/PK on a partitioned table must include the partition key (class_date)
    PRIMARY KEY (booking_id, class_date),
    CONSTRAINT one_booking_per_member_per_class UNIQUE (class_session_id, member_id, class_date),
    CONSTRAINT wl_pos_only_when_waitlisted CHECK (
        (status = 'WAITLISTED' AND waitlist_position IS NOT NULL AND waitlist_position > 0)
        OR (status <> 'WAITLISTED' AND waitlist_position IS NULL))
) PARTITION BY RANGE (class_date);

-- one partition per month covering all the data (13 months back) plus next 2 months
DO $$
DECLARE d DATE := date_trunc('month', CURRENT_DATE - INTERVAL '14 months')::date;
BEGIN
    WHILE d < (date_trunc('month', CURRENT_DATE) + INTERVAL '3 months')::date LOOP
        EXECUTE format('CREATE TABLE ironcore.%I PARTITION OF ironcore.class_booking FOR VALUES FROM (%L) TO (%L)',
                       'class_booking_' || to_char(d, 'YYYY_MM'), d, (d + INTERVAL '1 month')::date);
        d := (d + INTERVAL '1 month')::date;
    END LOOP;
END $$;
CREATE TABLE class_booking_default PARTITION OF class_booking DEFAULT;

INSERT INTO class_booking (booking_id, class_session_id, member_id, class_date, status, waitlist_position, booked_at)
SELECT booking_id, class_session_id, member_id, class_date, status, waitlist_position, booked_at FROM _booking_flat;
SELECT setval(pg_get_serial_sequence('ironcore.class_booking','booking_id'), (SELECT max(booking_id) FROM class_booking));

CREATE INDEX idx_p_booking_session ON class_booking (class_session_id);
CREATE INDEX idx_p_booking_member  ON class_booking (member_id);

-- triggers (same rules as P1; callers must now supply class_date, which must equal the session date)
CREATE OR REPLACE FUNCTION ironcore.check_membership_before_booking() RETURNS TRIGGER AS $f$
DECLARE class_day DATE; active BOOLEAN;
BEGIN
    SELECT (start_time AT TIME ZONE 'Africa/Lagos')::date INTO class_day FROM ironcore.class_session WHERE class_session_id = NEW.class_session_id;
    IF class_day IS NULL THEN RAISE EXCEPTION 'class_session_id % does not exist', NEW.class_session_id USING ERRCODE = 'foreign_key_violation'; END IF;
    IF NEW.class_date <> class_day THEN
        RAISE EXCEPTION 'class_date % does not match the session date %', NEW.class_date, class_day USING ERRCODE = 'check_violation'; END IF;
    SELECT EXISTS (SELECT 1 FROM ironcore.membership m WHERE m.member_id = NEW.member_id AND m.start_date <= class_day AND m.end_date >= class_day) INTO active;
    IF NOT active THEN
        RAISE EXCEPTION 'Member % has no active membership on % for class_session %', NEW.member_id, class_day, NEW.class_session_id USING ERRCODE = 'check_violation'; END IF;
    RETURN NEW;
END $f$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_membership_before_booking BEFORE INSERT ON ironcore.class_booking
    FOR EACH ROW EXECUTE FUNCTION ironcore.check_membership_before_booking();
CREATE TRIGGER trg_enforce_capacity BEFORE INSERT ON ironcore.class_booking
    FOR EACH ROW EXECUTE FUNCTION ironcore.enforce_capacity();
CREATE TRIGGER trg_promote_waitlist AFTER UPDATE OF status ON ironcore.class_booking
    FOR EACH ROW EXECUTE FUNCTION ironcore.promote_waitlist();

CREATE OR REPLACE VIEW ironcore.v_session_booking_count AS
SELECT s.class_session_id, s.capacity,
       COUNT(b.booking_id) FILTER (WHERE b.status = 'BOOKED')    AS booked,
       COUNT(b.booking_id) FILTER (WHERE b.status = 'WAITLISTED') AS waitlisted
FROM ironcore.class_session s LEFT JOIN ironcore.class_booking b ON b.class_session_id = s.class_session_id
GROUP BY s.class_session_id, s.capacity;

-- unpartitioned comparison copy, same data and the same index on class_date
ALTER TABLE _booking_flat RENAME TO class_booking_flat;
CREATE INDEX idx_flat_class_date ON class_booking_flat (class_date);
ANALYZE class_booking; ANALYZE class_booking_flat;
\endif

\echo ''
\echo '== Partitions and row counts =='
SELECT tableoid::regclass AS partition, COUNT(*) AS rows FROM class_booking GROUP BY tableoid ORDER BY 1;
SELECT 'rows in DEFAULT partition (must be 0)' AS check, COUNT(*) FROM class_booking_default;
SELECT 'total rows partitioned vs flat copy' AS check, (SELECT COUNT(*) FROM class_booking) AS partitioned, (SELECT COUNT(*) FROM class_booking_flat) AS flat;

\echo ''
\echo '== One-month query, PARTITIONED table (partition pruning: only the matching partition is read) =='
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON)
SELECT status, COUNT(*) FROM class_booking
WHERE class_date >= date_trunc('month', CURRENT_DATE - INTERVAL '3 months')::date
  AND class_date <  date_trunc('month', CURRENT_DATE - INTERVAL '2 months')::date
GROUP BY status;

\echo ''
\echo '== Same query, UNPARTITIONED copy (index on class_date) =='
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON)
SELECT status, COUNT(*) FROM class_booking_flat
WHERE class_date >= date_trunc('month', CURRENT_DATE - INTERVAL '3 months')::date
  AND class_date <  date_trunc('month', CURRENT_DATE - INTERVAL '2 months')::date
GROUP BY status;
