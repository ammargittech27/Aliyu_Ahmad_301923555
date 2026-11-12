#!/usr/bin/env python3
"""Six concurrency demos with TWO real PostgreSQL sessions (psycopg2) + threads. Every line is real output."""
import threading, time, sys
import psycopg2
from psycopg2 import errors, extensions

def conn(level=None):
    c = psycopg2.connect(host='/var/run/postgresql', dbname='ironcore', user='postgres')
    c.set_session(isolation_level=level or extensions.ISOLATION_LEVEL_READ_COMMITTED, autocommit=False)
    cur = c.cursor(); cur.execute("SET search_path=ironcore,public; SET timezone TO 'Africa/Lagos'"); c.commit()
    return c

adm = conn(); adm.autocommit = True
def q(sql, args=None, c=None):
    cur = (c or adm).cursor(); cur.execute(sql, args)
    return cur.fetchall() if cur.description else None
def reset(n=19):
    sid = q("SELECT reset_race_session(%s)", (n,))[0][0]
    day = q("SELECT (start_time AT TIME ZONE 'Africa/Lagos')::date FROM class_session WHERE class_session_id=%s",(sid,))[0][0]
    extra = [r[0] for r in q("""SELECT DISTINCT member_id FROM membership WHERE start_date<=%s AND end_date>=%s
                                 ORDER BY member_id OFFSET %s LIMIT 4""", (day, day, n))]
    return sid, extra
def counts(sid):
    r = q("""SELECT count(*) FILTER (WHERE status='BOOKED'), count(*) FILTER (WHERE status='WAITLISTED'), (SELECT capacity FROM class_session WHERE class_session_id=%s)
             FROM class_booking WHERE class_session_id=%s""", (sid, sid))[0]
    return f"BOOKED={r[0]} WAITLISTED={r[1]} capacity={r[2]}"
def log(*a): print(*a, flush=True)
def head(t): log("\n" + "="*8 + " " + t + " " + "="*8)

# ---------- Part 1: the bug (check-then-insert, no lock) ----------
head("PART 1 - THE BUG: two sessions book the LAST seat with a plain SELECT count + INSERT")
sid, ex = reset(19); log("start:", counts(sid))
a, b = conn(), conn()
for name, c, m in (("A", a, ex[0]), ("B", b, ex[1])):
    n = q("SELECT count(*) FROM class_booking WHERE class_session_id=%s AND status='BOOKED'", (sid,), c)[0][0]
    log(f"session {name}: sees {n} booked of 20 -> free seat, inserts member {m}")
for c, m in ((a, ex[0]), (b, ex[1])):
    q("INSERT INTO class_booking (class_session_id, member_id, status) VALUES (%s,%s,'BOOKED')", (sid, m), c)
a.commit(); b.commit()
log("after both commit:", counts(sid), "  <-- 21 BOOKED in a class of 20 (overbooked!)")

# ---------- Part 2: UNIQUE ----------
head("PART 2 - UNIQUE (class_session_id, member_id): the same member booked twice at once")
sid, ex = reset(19)
a, b = conn(), conn()
q("INSERT INTO class_booking (class_session_id, member_id, status) VALUES (%s,%s,'BOOKED')", (sid, ex[0]), a)
res = {}
def dup():
    try:
        q("INSERT INTO class_booking (class_session_id, member_id, status) VALUES (%s,%s,'BOOKED')", (sid, ex[0]), b); b.commit(); res['b'] = 'inserted'
    except errors.UniqueViolation as e:
        b.rollback(); res['b'] = 'UniqueViolation: ' + e.diag.constraint_name
t = threading.Thread(target=dup); t.start(); time.sleep(1)
log("session B is blocked waiting for A's uncommitted row...", "alive" if t.is_alive() else "not blocked")
a.commit(); t.join()
log("session B result:", res['b']); log("final:", counts(sid), "(one booking for that member)")

# ---------- Part 3: FOR UPDATE ----------
head("PART 3 - FIX 1: book_class() locks the class row (SELECT ... FOR UPDATE)")
sid, ex = reset(19)
a, b = conn(), conn(); out = {}
q("SELECT * FROM book_class(%s,%s)", (ex[0], sid), a)   # A holds the class-row lock until commit
def other():
    t0 = time.time(); r = q("SELECT out_status FROM book_class(%s,%s)", (ex[1], sid), b); b.commit(); out['b'] = (r[0][0], time.time()-t0)
t = threading.Thread(target=other); t.start(); time.sleep(1)
log("session B called book_class() and is waiting on the lock:", "yes" if t.is_alive() else "no")
a.commit(); t.join()
log(f"session B finished after the lock released: status={out['b'][0]} (waited {out['b'][1]:.1f}s)")
log("final:", counts(sid), "  <-- exactly 20 BOOKED, the late one is WAITLISTED")

# ---------- Part 4: SERIALIZABLE ----------
head("PART 4 - FIX 2: SERIALIZABLE isolation (one of the two is aborted and must retry)")
sid, ex = reset(19)
a, b = conn(extensions.ISOLATION_LEVEL_SERIALIZABLE), conn(extensions.ISOLATION_LEVEL_SERIALIZABLE)
for c in (a, b): q("SELECT count(*) FROM class_booking WHERE class_session_id=%s AND status='BOOKED'", (sid,), c)
q("INSERT INTO class_booking (class_session_id, member_id, status) VALUES (%s,%s,'BOOKED')", (sid, ex[0]), a)
q("INSERT INTO class_booking (class_session_id, member_id, status) VALUES (%s,%s,'BOOKED')", (sid, ex[1]), b)
outcome = []
for name, c in (("A", a), ("B", b)):
    try: c.commit(); outcome.append(f"{name}: COMMIT ok")
    except errors.SerializationFailure as e: c.rollback(); outcome.append(f"{name}: SerializationFailure (SQLSTATE 40001) - retry needed")
log("\n".join(outcome)); log("final:", counts(sid))

# ---------- Part 5: READ COMMITTED vs REPEATABLE READ ----------
head("PART 5 - READ COMMITTED vs REPEATABLE READ (non-repeatable read)")
for label, lvl in (("READ COMMITTED", extensions.ISOLATION_LEVEL_READ_COMMITTED), ("REPEATABLE READ", extensions.ISOLATION_LEVEL_REPEATABLE_READ)):
    sid, ex = reset(10)
    r, w = conn(lvl), conn()
    n1 = q("SELECT count(*) FROM class_booking WHERE class_session_id=%s AND status='BOOKED'", (sid,), r)[0][0]
    q("INSERT INTO class_booking (class_session_id, member_id, status) VALUES (%s,%s,'BOOKED')", (sid, ex[0]), w); w.commit()
    n2 = q("SELECT count(*) FROM class_booking WHERE class_session_id=%s AND status='BOOKED'", (sid,), r)[0][0]
    r.commit()
    log(f"{label}: reader's first count={n1}, after another session committed a booking, second count={n2}  -> {'CHANGED' if n1!=n2 else 'same snapshot'}")

# ---------- Part 6: deadlock ----------
head("PART 6 - DEADLOCK: two sessions lock the same two bookings in opposite order")
sid, ex = reset(19)
ids = [r[0] for r in q("SELECT booking_id FROM class_booking WHERE class_session_id=%s ORDER BY booking_id LIMIT 2", (sid,))]
a, b = conn(), conn(); res = {}
q("UPDATE class_booking SET booked_at=now() WHERE booking_id=%s", (ids[0],), a)
q("UPDATE class_booking SET booked_at=now() WHERE booking_id=%s", (ids[1],), b)
log(f"A locked booking {ids[0]}; B locked booking {ids[1]}")
def second(name, c, bid):
    try: q("UPDATE class_booking SET booked_at=now() WHERE booking_id=%s", (bid,), c); res[name] = 'got second lock'
    except errors.DeadlockDetected: c.rollback(); res[name] = 'DeadlockDetected (SQLSTATE 40P01) - victim rolled back'
ta = threading.Thread(target=second, args=("A", a, ids[1])); ta.start(); time.sleep(0.5)
tb = threading.Thread(target=second, args=("B", b, ids[0])); tb.start()
ta.join(); tb.join()
for c in (a, b): c.commit() if c.status != extensions.STATUS_READY else None
log("A:", res['A']); log("B:", res['B'])
log("fix: always lock bookings in the same order (ORDER BY booking_id ... FOR UPDATE) and the deadlock cannot happen.")
reset(19); log("\nAll six demos finished.")
