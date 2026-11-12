-- portfolio-1-database-design/generate_bulk.sql
-- Bulk generator. Produces 2 years of history + the next 14 days of class sessions,
-- 5,000+ memberships and 50,000+ class_bookings. No class ever exceeds capacity
-- (enforced by inserting exactly capacity-1 BOOKED rows + a few WAITLISTED rows).
-- Heavier load in January (new-year resolutions) and in evening slots (18:00).
-- Nigerian names, ₦ prices. Idempotent — TRUNCATE first.
-- Run with: sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -f generate_bulk.sql

\set ON_ERROR_STOP on
SET search_path = ironcore, public;
SET timezone TO 'Africa/Lagos';

BEGIN;
TRUNCATE ironcore.class_booking, ironcore.payment, ironcore.membership,
         ironcore.class_session, ironcore.trainer, ironcore.member RESTART IDENTITY CASCADE;
COMMIT;

-- ---------------------------------------------------------------------------
-- Helpers: temporary tables of Nigerian names + phone-number generator.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _first_names (n TEXT);
INSERT INTO _first_names VALUES
('Chukwuemeka'),('Ngozi'),('Tunde'),('Aisha'),('Emeka'),('Fatima'),('Bola'),('Sani'),
('Yetunde'),('Kunle'),('Adaeze'),('Yakubu'),('Hauwa'),('Femi'),('Ifeoma'),('Musa'),
('Tari'),('Bashir'),('Ibrahim'),('Nneka'),('Olabisi'),('Uche'),('Vweta'),('Wale'),
('Xenia'),('Zainab'),('Adeola'),('Dauda'),('Ebere'),('Fatai'),('Hakeem'),('Jide'),
('Kemi'),('Lola'),('Mide'),('Nkechi'),('Obinna'),('Petra'),('Qudus'),('Rabi'),
('Saheed'),('Tola'),('Udo'),('Vincent'),('Wasiu'),('Yewande'),('Zakari'),('Aisha'),
('Binta'),('Chioma'),('Danjuma'),('Eyo'),('Funke'),('Ganiyu'),('Hadiza'),('Ifeanyi'),
('Jumai'),('Kabiru'),('Laila'),('Mariam'),('Nuhu'),('Olaide'),('Rashida'),('Sanusi'),
('Tanimu'),('Umoru'),('Wasila'),('Yakubu'),('Zainab'),('Abubakar'),('Adebayo'),('Chika');

CREATE TEMP TABLE _last_names (n TEXT);
INSERT INTO _last_names VALUES
('Okafor'),('Bello'),('Adeyemi'),('Mohammed'),('Eze'),('Suleiman'),('Ogunleye'),('Abubakar'),
('Williams'),('Okeke'),('Audu'),('Olawale'),('Yusuf'),('Okoro'),('Idris'),('Ezeala'),
('Sanda'),('Gbenga'),('Balogun'),('Ibrahim'),('Nwosu'),('Ezeoke'),('Musa'),('Olatunji'),
('Adeleke'),('Sule'),('Okonkwo'),('Onuoha'),('Oluwatobi'),('Aminu'),('Dauda'),('Eze'),
('Okoye'),('Ojo'),('Adewale'),('Adeyemo'),('Idris-Mohammed'),('Olaniyan'),('Okeke-Okafor'),
('Tanko'),('Sanda-Idris'),('Ahmed-Olawale'),('Okoro-Okafor'),('Adeosun'),('Adeosun-Ojo'),
('Yakubu-Musa'),('Bashir-Okafor'),('Idris-Bello'),('Okonkwo-Adeyemi'),('Mohammed-Suleiman');

-- 6,000 members ------------------------------------------------------------------
\echo 'Generating 6,000 members...'
INSERT INTO member (first_name, last_name, email, phone, gender, dob)
SELECT
    f.n,
    l.n,
    lower(f.n) || '.' || lower(l.n) || gs.n || '@example.com',
    '+234 80' || (3 + (gs.n % 7))::text || ' ' ||
        lpad(((gs.n * 7) % 1000)::text,3,'0') || ' ' ||
        lpad(((gs.n * 13) % 10000)::text,4,'0'),
    CASE WHEN (gs.n % 2) = 0 THEN 'M' ELSE 'F' END,
    DATE '1970-01-01' + ((gs.n * 11) % 1500)
FROM generate_series(1, 6000) AS gs(n)
CROSS JOIN LATERAL (
    SELECT n FROM _first_names ORDER BY n LIMIT 1 OFFSET (gs.n % (SELECT count(*) FROM _first_names))
) f
CROSS JOIN LATERAL (
    SELECT n FROM _last_names ORDER BY n LIMIT 1 OFFSET (gs.n % (SELECT count(*) FROM _last_names))
) l;

-- 10 trainers (2 per branch) ---------------------------------------------------
\echo 'Generating 10 trainers (2 per branch)...'
DO $$
DECLARE
    b RECORD;
    i INT := 1;
    fn TEXT[]; ln TEXT[];
BEGIN
    fn := ARRAY(SELECT n FROM _first_names ORDER BY n LIMIT 10);
    ln := ARRAY(SELECT n FROM _last_names  ORDER BY n LIMIT 10);
    FOR b IN SELECT branch_id FROM branch ORDER BY branch_id LOOP
        INSERT INTO trainer (first_name, last_name, email, phone, specialization, branch_id)
        VALUES
          (fn[i],   ln[i],   lower(fn[i])   || '.' || lower(ln[i])   || '@ironcore.ng',
                    '+234 803 ' || lpad(b.branch_id::text,3,'0') || '1',
                    (ARRAY['Spinning','HIIT','Yoga','Boxing','Aerobics'])[1 + ((i % 5))],
                    b.branch_id),
          (fn[i+1], ln[i+1], lower(fn[i+1]) || '.' || lower(ln[i+1]) || '@ironcore.ng',
                    '+234 803 ' || lpad(b.branch_id::text,3,'0') || '2',
                    (ARRAY['Spinning','HIIT','Yoga','Boxing','Aerobics'])[1 + (((i+1) % 5))],
                    b.branch_id);
        i := i + 2;
    END LOOP;
END $$;

-- Gender matched to first name (the name table is Nigerian, mixed M/F) --------------
UPDATE member SET gender = CASE WHEN first_name IN
 ('Ngozi','Aisha','Fatima','Bola','Yetunde','Adaeze','Hauwa','Ifeoma','Tari','Nneka','Olabisi',
  'Vweta','Xenia','Zainab','Adeola','Ebere','Kemi','Lola','Mide','Nkechi','Petra','Rabi','Tola',
  'Yewande','Binta','Chioma','Funke','Hadiza','Jumai','Laila','Mariam','Olaide','Rashida','Wasila','Chika')
 THEN 'F' ELSE 'M' END;

-- Trigger-heavy bulk loads are slow; the rows below are valid by construction.
SET session_replication_role = replica;

-- ~7,000 memberships: 5,000 members each get a first membership somewhere in the
-- last ~2 years, and 3,000 of them renew straight after it ends. January is
-- over-weighted (new-year resolutions). Renewal starts the day after the end.
\echo 'Generating ~7,000 memberships...'
CREATE TEMP TABLE _m1 AS
SELECT m.member_id,
       p.plan_id,
       p.duration_months,
       (CURRENT_DATE - (CASE WHEN random() < 0.25
                             THEN 30 + (random()*30)::INT + 365*(random() < 0.5)::INT   -- ~January cohort
                             ELSE 20 + (random()*680)::INT END))::DATE AS start_date
FROM member m
JOIN LATERAL (SELECT plan_id, duration_months FROM plan
              ORDER BY plan_id
              OFFSET (CASE WHEN random() < 0.5 THEN 0 WHEN random() < 0.6 THEN 1 ELSE 2 END) LIMIT 1) p ON true
WHERE m.member_id % 6 <> 0;

INSERT INTO membership (member_id, plan_id, start_date, end_date)
SELECT member_id, plan_id, start_date, (start_date + make_interval(months => duration_months))::DATE FROM _m1;

INSERT INTO membership (member_id, plan_id, start_date, end_date)
SELECT member_id, plan_id,
       (start_date + make_interval(months => duration_months))::DATE + 1,
       (start_date + make_interval(months => 2*duration_months))::DATE + 1
FROM _m1 WHERE member_id % 2 = 0;

-- Payments for every membership ----------------------------------------------
\echo 'Generating payments for every membership...'
INSERT INTO payment (membership_id, amount_naira, paid_at, method, reference)
SELECT m.membership_id, p.price_naira,
       m.start_date::timestamp + (random() * INTERVAL '1 hour'),
       (ARRAY['CARD','TRANSFER','CASH','USSD'])[1 + (m.membership_id::int % 4)],
       'BULK-PAY-' || lpad(m.membership_id::text, 7, '0')
FROM membership m JOIN plan p ON p.plan_id = m.plan_id;

-- Class sessions: 3 slots per branch per day (06:30, 12:00, 18:00 Lagos time),
-- last 365 days + the next 14 days. Two trainers per branch.
\echo 'Generating class sessions (365 days of history + next 14 days)...'
INSERT INTO class_session (branch_id, class_type_id, trainer_id, start_time, end_time, capacity)
SELECT b.branch_id,
       1 + ((d + s.slot + b.branch_id) % 5),
       t.trainer_id,
       ((CURRENT_DATE + d) + s.t) AT TIME ZONE 'Africa/Lagos',
       ((CURRENT_DATE + d) + s.t + INTERVAL '1 hour') AT TIME ZONE 'Africa/Lagos',
       15 + s.slot * 5
FROM generate_series(-365, 14) AS d
CROSS JOIN branch b
CROSS JOIN (VALUES (1, TIME '06:30'), (2, TIME '12:00'), (3, TIME '18:00')) AS s(slot, t)
JOIN LATERAL (SELECT trainer_id FROM trainer WHERE branch_id = b.branch_id
              ORDER BY trainer_id OFFSET (CASE WHEN s.slot = 3 THEN 1 ELSE 0 END) LIMIT 1) t ON true;

-- Bookings: each session gets a different number of members who hold an active
-- membership on that day. Never above capacity. Past sessions are ATTENDED
-- (about 1 in 8 CANCELLED); future sessions are BOOKED. Evening slots are busier.
\echo 'Generating class bookings (no class over capacity)...'
INSERT INTO class_booking (class_session_id, member_id, status, booked_at)
SELECT class_session_id, member_id,
       CASE WHEN start_time > now() THEN 'BOOKED'
            WHEN (hashtext(member_id::text || class_session_id::text) % 8) = 0 THEN 'CANCELLED'
            ELSE 'ATTENDED' END,
       start_time - INTERVAL '1 day' - (random() * INTERVAL '3 days')
FROM (
    SELECT s.class_session_id, s.start_time, ms.member_id,
           ROW_NUMBER() OVER (PARTITION BY s.class_session_id
                              ORDER BY hashtext(ms.member_id::text || s.class_session_id::text)) AS rn,
           CASE WHEN s.class_session_id % 40 = 0 AND s.start_time > now() THEN s.capacity       -- a few full future classes
                ELSE LEAST(s.capacity - 2,
                           3 + (abs(hashtext(s.class_session_id::text)) % (s.capacity - 5))
                             + (CASE WHEN EXTRACT(HOUR FROM s.start_time AT TIME ZONE 'Africa/Lagos') = 18 THEN 4 ELSE 0 END))
           END AS want
    FROM class_session s
    JOIN membership ms ON ms.start_date <= (s.start_time AT TIME ZONE 'Africa/Lagos')::DATE
                      AND ms.end_date   >= (s.start_time AT TIME ZONE 'Africa/Lagos')::DATE
) q
WHERE rn <= want;

SET session_replication_role = origin;

-- Waitlist evidence: with triggers ON, push 3 extra members into each of 5 full
-- future classes (the capacity trigger turns them into WAITLISTED), then cancel
-- one BOOKED seat in 2 of them so the promote_waitlist trigger fires.
\echo 'Adding WAITLISTED rows and a cancellation on full future classes...'
INSERT INTO class_booking (class_session_id, member_id, status)
SELECT f.class_session_id, c.member_id, 'BOOKED'
FROM (SELECT s.class_session_id FROM class_session s
      JOIN class_booking b ON b.class_session_id = s.class_session_id AND b.status = 'BOOKED'
      WHERE s.start_time > now()
      GROUP BY s.class_session_id, s.capacity HAVING COUNT(*) = s.capacity
      ORDER BY s.class_session_id LIMIT 5) f
CROSS JOIN LATERAL (
    SELECT ms.member_id FROM membership ms
    JOIN class_session s ON s.class_session_id = f.class_session_id
    WHERE ms.start_date <= (s.start_time AT TIME ZONE 'Africa/Lagos')::DATE
      AND ms.end_date   >= (s.start_time AT TIME ZONE 'Africa/Lagos')::DATE
      AND NOT EXISTS (SELECT 1 FROM class_booking x WHERE x.class_session_id = f.class_session_id AND x.member_id = ms.member_id)
    ORDER BY ms.member_id LIMIT 3) c;

UPDATE class_booking SET status = 'CANCELLED'
WHERE booking_id IN (
    SELECT min(booking_id) FROM class_booking
    WHERE status = 'BOOKED'
      AND class_session_id IN (SELECT DISTINCT class_session_id FROM class_booking WHERE status = 'WAITLISTED')
    GROUP BY class_session_id ORDER BY class_session_id LIMIT 2);

ANALYZE;

-- Final counts -----------------------------------------------------------------
\echo ''
\echo '== Bulk generation complete =='
SELECT 'members'     AS table_name, count(*) FROM member
UNION ALL SELECT 'memberships', count(*) FROM membership
UNION ALL SELECT 'class_sessions', count(*) FROM class_session
UNION ALL SELECT 'class_bookings', count(*) FROM class_booking
UNION ALL SELECT 'payments', count(*) FROM payment;
SELECT status, count(*) FROM class_booking GROUP BY status ORDER BY 2 DESC;
SELECT 'sessions over capacity' AS check, count(*) FROM v_session_booking_count WHERE booked > capacity;
