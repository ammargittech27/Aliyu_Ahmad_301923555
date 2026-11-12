-- portfolio-1-database-design/constraint_tests.sql
-- Each test builds its own data, expects ONE specific constraint/trigger to fire, and
-- RAISES (stopping the run) if the wrong error or no error happens. Each runs in a
-- transaction that is rolled back, so the bulk data is untouched.
\set ON_ERROR_STOP on
SET search_path = ironcore, public;
SET timezone TO 'Africa/Lagos';

\echo '== Test 1: a member cannot hold two overlapping memberships (EXCLUSION no_overlap_membership) =='
BEGIN;
DO $$
DECLARE m BIGINT; p INT;
BEGIN
  INSERT INTO member (first_name,last_name,email) VALUES ('Test','One','t1@x.com') RETURNING member_id INTO m;
  SELECT plan_id INTO p FROM plan ORDER BY plan_id LIMIT 1;
  INSERT INTO membership (member_id,plan_id,start_date,end_date) VALUES (m,p,CURRENT_DATE,CURRENT_DATE+30);  -- control: must succeed
  RAISE NOTICE 'control OK: first membership inserted';
  BEGIN
    INSERT INTO membership (member_id,plan_id,start_date,end_date) VALUES (m,p,CURRENT_DATE+10,CURRENT_DATE+50);
    RAISE EXCEPTION 'FAIL: overlapping membership was accepted';
  EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'PASS: overlapping membership rejected by no_overlap_membership';
  END;
END $$;
ROLLBACK;

\echo '== Test 2: a trainer cannot teach two overlapping sessions (EXCLUSION no_overlap_trainer) =='
BEGIN;
DO $$
DECLARE b INT; c INT; t BIGINT; ts TIMESTAMPTZ := (CURRENT_DATE + 60 + TIME '03:00') AT TIME ZONE 'Africa/Lagos';
BEGIN
  SELECT branch_id INTO b FROM branch ORDER BY 1 LIMIT 1;
  SELECT class_type_id INTO c FROM class_type ORDER BY 1 LIMIT 1;
  INSERT INTO trainer (first_name,last_name,email,branch_id) VALUES ('Test','Trainer','t2@x.com',b) RETURNING trainer_id INTO t;
  INSERT INTO class_session (branch_id,class_type_id,trainer_id,start_time,end_time,capacity) VALUES (b,c,t,ts,ts+INTERVAL '60 min',20);
  RAISE NOTICE 'control OK: first session inserted';
  BEGIN
    INSERT INTO class_session (branch_id,class_type_id,trainer_id,start_time,end_time,capacity) VALUES (b,c,t,ts+INTERVAL '30 min',ts+INTERVAL '90 min',20);
    RAISE EXCEPTION 'FAIL: overlapping trainer session was accepted';
  EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'PASS: overlapping trainer session rejected by no_overlap_trainer';
  END;
END $$;
ROLLBACK;

\echo '== Test 3: no booking without an active membership on the class day (trigger) =='
BEGIN;
DO $$
DECLARE m BIGINT; s BIGINT;
BEGIN
  INSERT INTO member (first_name,last_name,email) VALUES ('Test','Three','t3@x.com') RETURNING member_id INTO m;
  SELECT class_session_id INTO s FROM class_session WHERE start_time > now() ORDER BY start_time LIMIT 1;
  BEGIN
    INSERT INTO class_booking (class_session_id,member_id,status) VALUES (s,m,'BOOKED');
    RAISE EXCEPTION 'FAIL: booking without membership was accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE '%no active membership%' THEN RAISE EXCEPTION 'FAIL: wrong error: %', SQLERRM; END IF;
    RAISE NOTICE 'PASS: rejected by trigger: %', SQLERRM;
  END;
END $$;
ROLLBACK;

\echo '== Test 4: same member cannot book the same class twice (UNIQUE one_booking_per_member_per_class) =='
BEGIN;
DO $$
DECLARE b INT; c INT; t BIGINT; s BIGINT; m BIGINT; ts TIMESTAMPTZ := (CURRENT_DATE + 61 + TIME '03:00') AT TIME ZONE 'Africa/Lagos';
BEGIN
  SELECT branch_id INTO b FROM branch ORDER BY 1 LIMIT 1;
  SELECT class_type_id INTO c FROM class_type ORDER BY 1 LIMIT 1;
  INSERT INTO trainer (first_name,last_name,email,branch_id) VALUES ('Test','Trainer4','t4t@x.com',b) RETURNING trainer_id INTO t;
  INSERT INTO class_session (branch_id,class_type_id,trainer_id,start_time,end_time,capacity) VALUES (b,c,t,ts,ts+INTERVAL '60 min',20) RETURNING class_session_id INTO s;
  INSERT INTO member (first_name,last_name,email) VALUES ('Test','Four','t4@x.com') RETURNING member_id INTO m;
  INSERT INTO membership (member_id,plan_id,start_date,end_date) VALUES (m,(SELECT plan_id FROM plan ORDER BY 1 LIMIT 1),CURRENT_DATE,CURRENT_DATE+90);
  INSERT INTO class_booking (class_session_id,member_id,status) VALUES (s,m,'BOOKED');   -- control: must succeed
  RAISE NOTICE 'control OK: first booking inserted';
  BEGIN
    INSERT INTO class_booking (class_session_id,member_id,status) VALUES (s,m,'BOOKED');
    RAISE EXCEPTION 'FAIL: duplicate booking was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: duplicate booking rejected by one_booking_per_member_per_class';
  END;
END $$;
ROLLBACK;

\echo '== Test 5: payment amount must be > 0 (CHECK) =='
BEGIN;
DO $$
DECLARE m BIGINT; ms BIGINT;
BEGIN
  INSERT INTO member (first_name,last_name,email) VALUES ('Test','Five','t5@x.com') RETURNING member_id INTO m;
  INSERT INTO membership (member_id,plan_id,start_date,end_date) VALUES (m,(SELECT plan_id FROM plan ORDER BY 1 LIMIT 1),CURRENT_DATE,CURRENT_DATE+30) RETURNING membership_id INTO ms;
  INSERT INTO payment (membership_id,amount_naira,method,reference) VALUES (ms,15000,'CASH','TEST-OK-5');   -- control: must succeed
  RAISE NOTICE 'control OK: valid payment inserted';
  BEGIN
    INSERT INTO payment (membership_id,amount_naira,method,reference) VALUES (ms,0,'CASH','TEST-ZERO-5');
    RAISE EXCEPTION 'FAIL: zero payment was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: zero payment rejected by payment_amount_naira_check';
  END;
END $$;
ROLLBACK;

\echo '== Test 6: plan price must be > 0 (CHECK) =='
BEGIN;
DO $$
BEGIN
  BEGIN
    INSERT INTO plan (name,duration_months,price_naira) VALUES ('BadPlan',1,0);
    RAISE EXCEPTION 'FAIL: zero-price plan was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: zero-price plan rejected by plan_price_naira_check';
  END;
END $$;
ROLLBACK;

\echo '== Test 7: cancelling a BOOKED row promotes WAITLISTED position 1 (own data, capacity 2) =='
BEGIN;
DO $$
DECLARE b INT; c INT; t BIGINT; s BIGINT; m1 BIGINT; m2 BIGINT; m3 BIGINT; st TEXT; pos INT;
        ts TIMESTAMPTZ := (CURRENT_DATE + 62 + TIME '03:00') AT TIME ZONE 'Africa/Lagos';
BEGIN
  SELECT branch_id INTO b FROM branch ORDER BY 1 LIMIT 1;
  SELECT class_type_id INTO c FROM class_type ORDER BY 1 LIMIT 1;
  INSERT INTO trainer (first_name,last_name,email,branch_id) VALUES ('Test','Trainer7','t7t@x.com',b) RETURNING trainer_id INTO t;
  INSERT INTO class_session (branch_id,class_type_id,trainer_id,start_time,end_time,capacity) VALUES (b,c,t,ts,ts+INTERVAL '60 min',2) RETURNING class_session_id INTO s;
  INSERT INTO member (first_name,last_name,email) VALUES ('Promote','A','pa@x.com') RETURNING member_id INTO m1;
  INSERT INTO member (first_name,last_name,email) VALUES ('Promote','B','pb@x.com') RETURNING member_id INTO m2;
  INSERT INTO member (first_name,last_name,email) VALUES ('Promote','C','pc@x.com') RETURNING member_id INTO m3;
  INSERT INTO membership (member_id,plan_id,start_date,end_date)
    SELECT x,(SELECT plan_id FROM plan ORDER BY 1 LIMIT 1),CURRENT_DATE,CURRENT_DATE+90 FROM unnest(ARRAY[m1,m2,m3]) x;
  INSERT INTO class_booking (class_session_id,member_id,status) VALUES (s,m1,'BOOKED'),(s,m2,'BOOKED');
  INSERT INTO class_booking (class_session_id,member_id,status) VALUES (s,m3,'BOOKED');   -- full: trigger must waitlist it
  SELECT status, waitlist_position INTO st, pos FROM class_booking WHERE class_session_id=s AND member_id=m3;
  IF st <> 'WAITLISTED' OR pos <> 1 THEN RAISE EXCEPTION 'FAIL: third member should be WAITLISTED position 1, got % %', st, pos; END IF;
  RAISE NOTICE 'control OK: third booking became WAITLISTED position 1';
  UPDATE class_booking SET status='CANCELLED' WHERE class_session_id=s AND member_id=m1;
  SELECT status INTO st FROM class_booking WHERE class_session_id=s AND member_id=m3;
  IF st <> 'BOOKED' THEN RAISE EXCEPTION 'FAIL: waitlisted member was not promoted (status %)', st; END IF;
  RAISE NOTICE 'PASS: cancellation promoted the waitlisted member to BOOKED';
END $$;
ROLLBACK;

\echo ''
\echo '== All 7 constraint tests passed =='
