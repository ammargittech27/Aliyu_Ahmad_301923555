-- portfolio-1-database-design/seed.sql
-- Small deterministic seed: 5 branches, 10 trainers, 5 class_types, 3 plans,
-- 30 members, ~30 memberships and ~40 class_sessions spread across the next 14 days.
-- Designed so the bulk generator can run afterwards on a non-empty schema.
-- Run with: sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -f seed.sql

\set ON_ERROR_STOP on
SET search_path = ironcore, public;
BEGIN;

-- 5 branches ------------------------------------------------------------------
INSERT INTO branch (name, city, area, address, phone) VALUES
('IronCore Wuse',     'Abuja',  'Wuse',     '21 Adetokunbo Ademola Crescent, Wuse II, Abuja', '+234 803 111 1001'),
('IronCore Gwarinpa',  'Abuja',  'Gwarinpa', 'Block C, 1st Avenue, Gwarinpa, Abuja',           '+234 803 111 1002'),
('IronCore Kano',      'Kano',   'Kano City','12 Bank Road, Nasarawa, Kano',                   '+234 803 111 1003'),
('IronCore Kaduna',    'Kaduna', 'Kaduna City','5 Ahmadu Bello Way, Kaduna',                   '+234 803 111 1004'),
('IronCore Lekki',     'Lagos',  'Lekki',    'Lekki Phase 1, Lagos',                            '+234 803 111 1005');

-- 3 plans (₦) -----------------------------------------------------------------
INSERT INTO plan (name, duration_months, price_naira) VALUES
('Monthly',   1,  15000.00),
('Quarterly', 3,  40000.00),
('Annual',   12, 150000.00);

-- 5 class types ---------------------------------------------------------------
INSERT INTO class_type (name, description, default_duration_min) VALUES
('Spinning',  'Indoor cycling class',                  45),
('HIIT',      'High-intensity interval training',      45),
('Yoga',      'Vinyasa & restorative yoga',            60),
('Boxing',    'Boxing fundamentals & pad work',         60),
('Aerobics',  'Low-impact aerobics',                    45);

-- 10 trainers (2 per branch) --------------------------------------------------
-- trainer_id is BIGSERIAL — let DB assign, use a sub-query on branch.
DO $$
DECLARE
    b RECORD;
    specs TEXT[] := ARRAY['Spinning','HIIT','Yoga','Boxing','Aerobics'];
    i INT;
    fn TEXT[] := ARRAY['Chuka','Ngozi','Tunde','Aisha','Emeka','Fatima','Bola','Sani','Yetunde','Kunle','Adaeze','Yakubu','Hauwa','Femi','Ifeoma','Musa','Tari','Bashir','Ibrahim','Nneka'];
    ln TEXT[] := ARRAY['Okafor','Bello','Adeyemi','Mohammed','Eze','Suleiman','Ogunleye','Abubakar','Williams','Okeke','Audu','Olawale','Yusuf','Okoro','Idris','Ezeala','Sanda','Gbenga','Balogun','Ibrahim'];
BEGIN
    i := 1;
    FOR b IN SELECT branch_id, area FROM branch ORDER BY branch_id LOOP
        INSERT INTO trainer (first_name, last_name, email, phone, specialization, branch_id)
        VALUES
          (fn[i],   ln[i],   lower(fn[i])   || '.' || lower(ln[i])   || '@ironcore.ng', '+234 803 222 ' || lpad(b.branch_id::text,3,'0') || '1', specs[(i % 5)+1], b.branch_id),
          (fn[i+1], ln[i+1], lower(fn[i+1]) || '.' || lower(ln[i+1]) || '@ironcore.ng', '+234 803 222 ' || lpad(b.branch_id::text,3,'0') || '2', specs[((i+1) % 5)+1], b.branch_id);
        i := i + 2;
    END LOOP;
END $$;

-- 30 deterministic members ----------------------------------------------------
INSERT INTO member (first_name, last_name, email, phone, gender, dob)
SELECT
    fn, ln,
    lower(fn) || '.' || lower(ln) || n || '@example.com',
    '+234 803 ' || lpad((n % 999)::text,3,'0') || ' ' || lpad((n % 9999)::text,4,'0'),
    CASE WHEN n % 2 = 0 THEN 'M' ELSE 'F' END,
    DATE '1990-01-01' + (n % 365 * 7)
FROM (
    SELECT n,
           (ARRAY['Ade','Bola','Chioma','Dauda','Emeka','Fatima','Gbenga','Hauwa','Ifeoma','Jide',
                  'Kunle','Lola','Musa','Nneka','Ola','Petra','Qudus','Rabi','Sani','Tunde',
                  'Uche','Vweta','Wale','Xenia','Yakubu','Zainab','Aisha','Bashir','Chika','Dapo'])[n] AS fn,
           (ARRAY['Okafor','Bello','Adeyemi','Mohammed','Eze','Suleiman','Ogunleye','Abubakar',
                  'Williams','Okeke','Audu','Olawale','Yusuf','Okoro','Idris','Ezeala','Sanda',
                  'Gbenga','Balogun','Ibrahim','Nwosu','Ezeoke','Musa','Olatunji','Adeleke','Sule',
                  'Okonkwo','Onuoha','Okafor-Okoye','Oluwatobi'])[n] AS ln
    FROM generate_series(1, 30) AS n
) s;

-- 30 memberships covering "now" so members can book classes today ------------
INSERT INTO membership (member_id, plan_id, start_date, end_date)
SELECT
    m.member_id,
    (ARRAY(SELECT plan_id FROM plan ORDER BY plan_id))[1 + (m.member_id::int % 3)],
    CURRENT_DATE - (m.member_id::int % 60),
    CASE (m.member_id::int % 3)
      WHEN 0 THEN CURRENT_DATE - (m.member_id::int % 60) + INTERVAL '1 month'
      WHEN 1 THEN CURRENT_DATE - (m.member_id::int % 60) + INTERVAL '3 months'
      ELSE        CURRENT_DATE - (m.member_id::int % 60) + INTERVAL '12 months'
    END
FROM member m
ORDER BY m.member_id
LIMIT 30;

-- 30 payments for those memberships -------------------------------------------
INSERT INTO payment (membership_id, amount_naira, paid_at, method, reference)
SELECT
    m.membership_id,
    p.price_naira,
    m.start_date::timestamp,
    (ARRAY['CARD','TRANSFER','CASH','USSD'])[1 + (m.membership_id::int % 4)],
    'SEED-' || lpad(m.membership_id::text, 6, '0')
FROM membership m
JOIN plan p ON p.plan_id = m.plan_id
ORDER BY m.membership_id
LIMIT 30;

-- Class sessions for the next 14 days: 3 per branch per day --------------------
-- Capacity alternates 15/20/25. Times: 06:30, 12:00, 18:00 (evening bias).
DO $$
DECLARE
    d INT;       -- days ahead
    b INT;       -- branch
    s INT;       -- session slot 1..3
    start_ts     TIMESTAMPTZ;
    dur          INT;
    cap          INT;
    trainer_pick BIGINT;
    ct_pick      INT;
BEGIN
    FOR d IN 0..13 LOOP
        FOR b IN SELECT branch_id FROM branch ORDER BY branch_id LOOP
            FOR s IN 1..3 LOOP
                -- Slot 1 = 06:30, slot 2 = 12:00, slot 3 = 18:00 (evening busiest)
                start_ts := (CURRENT_DATE + d) || ' ' ||
                    CASE s WHEN 1 THEN '06:30' WHEN 2 THEN '12:00' ELSE '18:00' END;
                start_ts := (CURRENT_DATE + d)::timestamp + (s - 1) * INTERVAL '1 hour' * 0
                          + CASE s WHEN 1 THEN INTERVAL '6 hours 30 minutes'
                                   WHEN 2 THEN INTERVAL '12 hours'
                                   ELSE INTERVAL '18 hours' END;
                dur := 60;
                cap := 15 + (s * 5);                       -- 20, 25, 30
                -- Pick the first trainer at the branch and a class type based on slot
                SELECT trainer_id INTO trainer_pick
                FROM trainer WHERE branch_id = b ORDER BY trainer_id LIMIT 1 OFFSET ((s - 1) % 2);
                SELECT class_type_id INTO ct_pick FROM class_type
                ORDER BY class_type_id LIMIT 1 OFFSET ((d + s + b) % 5);

                INSERT INTO class_session
                    (branch_id, class_type_id, trainer_id, start_time, end_time, capacity)
                VALUES (b, ct_pick, trainer_pick,
                        start_ts, start_ts + (dur || ' minutes')::interval, cap);
            END LOOP;
        END LOOP;
    END LOOP;
END $$;

COMMIT;
\echo 'Seed loaded: 5 branches, 10 trainers, 5 class_types, 3 plans, 30 members, 30 memberships, 30 payments, ~210 class sessions (next 14 days).'
