-- portfolio-1-database-design/schema.sql
-- IronCore Fitness — full relational schema for 9 tables, 3NF, all constraints.
-- Idempotent: DROP ... CASCADE first, then re-create. Connect via Unix socket.
-- Run with:
--   sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -f schema.sql

\set ON_ERROR_STOP on
BEGIN;
DROP SCHEMA IF EXISTS ironcore CASCADE;
CREATE SCHEMA ironcore;
SET search_path = ironcore, public;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. branch -------------------------------------------------------------------
CREATE TABLE branch (
    branch_id   SERIAL      PRIMARY KEY,
    name        TEXT        NOT NULL,
    city        TEXT        NOT NULL,
    area        TEXT        NOT NULL,
    address     TEXT,
    phone       TEXT,
    CONSTRAINT uk_branch_name_area UNIQUE (name, area)
);

-- 2. member -------------------------------------------------------------------
CREATE TABLE member (
    member_id   BIGSERIAL    PRIMARY KEY,
    first_name  TEXT        NOT NULL,
    last_name   TEXT        NOT NULL,
    email       TEXT        NOT NULL UNIQUE,
    phone       TEXT,
    gender      CHAR(1)     CHECK (gender IN ('M','F','O')),
    dob         DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. plan ---------------------------------------------------------------------
CREATE TABLE plan (
    plan_id             SERIAL        PRIMARY KEY,
    name                TEXT          NOT NULL UNIQUE,
    duration_months     INT           NOT NULL CHECK (duration_months > 0),
    price_naira         NUMERIC(12,2) NOT NULL CHECK (price_naira > 0)
);

-- 4. membership ---------------------------------------------------------------
-- One membership = (member, plan, start_date, end_date).
-- Exclusion constraint prevents a member from holding two overlapping memberships.
CREATE TABLE membership (
    membership_id   BIGSERIAL    PRIMARY KEY,
    member_id       BIGINT       NOT NULL REFERENCES member(member_id),
    plan_id         INT          NOT NULL REFERENCES plan(plan_id),
    start_date      DATE         NOT NULL,
    end_date        DATE         NOT NULL,
    CONSTRAINT membership_date_order   CHECK (end_date > start_date),
    CONSTRAINT no_overlap_membership
        EXCLUDE USING gist (
            member_id   WITH =,
            daterange(start_date, end_date, '[]') WITH &&
        )
);

-- 5. trainer ------------------------------------------------------------------
CREATE TABLE trainer (
    trainer_id      BIGSERIAL   PRIMARY KEY,
    first_name      TEXT        NOT NULL,
    last_name       TEXT        NOT NULL,
    email           TEXT        NOT NULL UNIQUE,
    phone           TEXT,
    specialization  TEXT,
    branch_id       INT         NOT NULL REFERENCES branch(branch_id)
);

-- 6. class_type ---------------------------------------------------------------
CREATE TABLE class_type (
    class_type_id           SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    description             TEXT,
    default_duration_min    INT     NOT NULL CHECK (default_duration_min > 0)
);

-- 7. class_session -----------------------------------------------------------
-- A scheduled class at a branch, taught by one trainer, with a capacity.
-- Trainer cannot teach two overlapping sessions (tstzrange exclusion).
CREATE TABLE class_session (
    class_session_id    BIGSERIAL    PRIMARY KEY,
    branch_id           INT          NOT NULL REFERENCES branch(branch_id),
    class_type_id       INT          NOT NULL REFERENCES class_type(class_type_id),
    trainer_id          BIGINT       NOT NULL REFERENCES trainer(trainer_id),
    start_time          TIMESTAMPTZ  NOT NULL,
    end_time            TIMESTAMPTZ  NOT NULL,
    capacity            INT          NOT NULL CHECK (capacity > 0),
    CONSTRAINT class_time_order CHECK (end_time > start_time),
    CONSTRAINT no_overlap_trainer
        EXCLUDE USING gist (
            trainer_id  WITH =,
            tstzrange(start_time, end_time, '[]') WITH &&
        )
);

-- 8. class_booking ------------------------------------------------------------
-- status: BOOKED | WAITLISTED | CANCELLED | ATTENDED
-- waitlist_position is NULL unless status = 'WAITLISTED'
-- UNIQUE (class_session_id, member_id) enforces "one booking per member per class"
CREATE TABLE class_booking (
    booking_id          BIGSERIAL    PRIMARY KEY,
    class_session_id    BIGINT       NOT NULL REFERENCES class_session(class_session_id),
    member_id           BIGINT       NOT NULL REFERENCES member(member_id),
    status              TEXT         NOT NULL
                        CHECK (status IN ('BOOKED','WAITLISTED','CANCELLED','ATTENDED')),
    waitlist_position   INT,
    booked_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT one_booking_per_member_per_class
        UNIQUE (class_session_id, member_id),
    CONSTRAINT wl_pos_only_when_waitlisted CHECK (
        (status = 'WAITLISTED'  AND waitlist_position IS NOT NULL AND waitlist_position > 0)
        OR
        (status <> 'WAITLISTED' AND waitlist_position IS NULL)
    )
);

-- 9. payment ------------------------------------------------------------------
CREATE TABLE payment (
    payment_id      BIGSERIAL    PRIMARY KEY,
    membership_id   BIGINT       NOT NULL REFERENCES membership(membership_id),
    amount_naira    NUMERIC(12,2) NOT NULL CHECK (amount_naira > 0),
    paid_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    method          TEXT         NOT NULL CHECK (method IN ('CARD','TRANSFER','CASH','USSD')),
    reference       TEXT         NOT NULL UNIQUE
);

-- Helpful indexes (P2 adds the analytical ones) ------------------------------
CREATE INDEX idx_membership_member      ON membership(member_id);
CREATE INDEX idx_membership_dates       ON membership(start_date, end_date);
CREATE INDEX idx_class_session_branch   ON class_session(branch_id);
CREATE INDEX idx_class_session_trainer  ON class_session(trainer_id);
CREATE INDEX idx_class_session_time     ON class_session(start_time);
CREATE INDEX idx_booking_session         ON class_booking(class_session_id);
CREATE INDEX idx_booking_member         ON class_booking(member_id);
CREATE INDEX idx_booking_status          ON class_booking(status);

COMMIT;

-- ============================================================================
-- Trigger 1: a member can book a class only if they have an active membership
-- on the day of the class. (BEFORE INSERT, before capacity check.)
-- ============================================================================
CREATE OR REPLACE FUNCTION ironcore.check_membership_before_booking()
RETURNS TRIGGER AS $$
DECLARE
    class_day DATE;
    active    BOOLEAN;
BEGIN
    SELECT DATE(start_time) INTO class_day
    FROM ironcore.class_session
    WHERE class_session_id = NEW.class_session_id;

    IF class_day IS NULL THEN
        RAISE EXCEPTION 'class_session_id % does not exist', NEW.class_session_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM ironcore.membership m
        WHERE m.member_id   = NEW.member_id
          AND m.start_date <= class_day
          AND m.end_date   >= class_day
    ) INTO active;

    IF NOT active THEN
        RAISE EXCEPTION
            'Member % has no active membership on % for class_session %',
            NEW.member_id, class_day, NEW.class_session_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Trigger 2: booked places never exceed capacity.
-- If the class is already full, the new booking becomes WAITLISTED with the
-- next waitlist_position. If there is room, status is forced to BOOKED and the
-- position is cleared. (BEFORE INSERT.)
-- ============================================================================
CREATE OR REPLACE FUNCTION ironcore.enforce_capacity()
RETURNS TRIGGER AS $$
DECLARE
    cap           INT;
    current_booked INT;
    next_pos      INT;
BEGIN
    SELECT capacity INTO cap
    FROM ironcore.class_session
    WHERE class_session_id = NEW.class_session_id;

    SELECT COUNT(*) INTO current_booked
    FROM ironcore.class_booking
    WHERE class_session_id = NEW.class_session_id
      AND status = 'BOOKED';

    -- CANCELLED or ATTENDED are explicit caller intents — do not override.
    IF NEW.status IN ('CANCELLED','ATTENDED') THEN
        NEW.waitlist_position := NULL;
        RETURN NEW;
    END IF;

    IF current_booked >= cap THEN
        SELECT COALESCE(MAX(waitlist_position), 0) + 1 INTO next_pos
        FROM ironcore.class_booking
        WHERE class_session_id = NEW.class_session_id
          AND status = 'WAITLISTED';

        NEW.status            := 'WAITLISTED';
        NEW.waitlist_position := next_pos;
    ELSE
        NEW.status            := 'BOOKED';
        NEW.waitlist_position := NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Trigger 3: when a BOOKED member CANCELS, promote the first WAITLISTED member
-- (min position) to BOOKED and shift the remaining waitlist positions down by 1.
-- (AFTER UPDATE OF status.)
-- ============================================================================
CREATE OR REPLACE FUNCTION ironcore.promote_waitlist()
RETURNS TRIGGER AS $$
DECLARE
    next_booking_id BIGINT;
    next_pos        INT;
BEGIN
    IF (OLD.status = 'BOOKED' AND NEW.status = 'CANCELLED') THEN
        -- Pick the lowest waitlist_position (FOR UPDATE to be safe under concurrency).
        SELECT booking_id, waitlist_position
          INTO next_booking_id, next_pos
        FROM ironcore.class_booking
        WHERE class_session_id = NEW.class_session_id
          AND status = 'WAITLISTED'
        ORDER BY waitlist_position ASC
        LIMIT 1
        FOR UPDATE;

        IF next_booking_id IS NOT NULL THEN
            UPDATE ironcore.class_booking
               SET status = 'BOOKED', waitlist_position = NULL
             WHERE booking_id = next_booking_id;

            -- Shift down everyone behind the promoted slot.
            UPDATE ironcore.class_booking
               SET waitlist_position = waitlist_position - 1
             WHERE class_session_id = NEW.class_session_id
               AND status = 'WAITLISTED'
               AND waitlist_position > next_pos;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger ordering: trigger names are fired alphabetically within the same
-- event/timing. enforce_capacity (e) fires before promote_waitlist (p) but only
-- on INSERT vs UPDATE respectively so they don't interfere. check_membership
-- (c) fires first on BEFORE INSERT, so it can reject before capacity mutation.
CREATE TRIGGER trg_check_membership_before_booking
BEFORE INSERT ON ironcore.class_booking
FOR EACH ROW EXECUTE FUNCTION ironcore.check_membership_before_booking();

CREATE TRIGGER trg_enforce_capacity
BEFORE INSERT ON ironcore.class_booking
FOR EACH ROW EXECUTE FUNCTION ironcore.enforce_capacity();

CREATE TRIGGER trg_promote_waitlist
AFTER UPDATE OF status ON ironcore.class_booking
FOR EACH ROW EXECUTE FUNCTION ironcore.promote_waitlist();

-- Helpful views used by queries in P2 and the bulk generator in P1.
CREATE OR REPLACE VIEW ironcore.v_active_membership AS
SELECT m.*,
       p.name AS plan_name,
       p.price_naira
FROM   ironcore.membership m
JOIN   ironcore.plan p ON p.plan_id = m.plan_id;

CREATE OR REPLACE VIEW ironcore.v_session_booking_count AS
SELECT s.class_session_id,
       s.capacity,
       COUNT(b.booking_id) FILTER (WHERE b.status = 'BOOKED')    AS booked,
       COUNT(b.booking_id) FILTER (WHERE b.status = 'WAITLISTED') AS waitlisted
FROM   ironcore.class_session s
LEFT JOIN ironcore.class_booking b ON b.class_session_id = s.class_session_id
GROUP BY s.class_session_id, s.capacity;

\echo 'Schema ironcore created with 9 tables + 3 triggers + 2 views.'
