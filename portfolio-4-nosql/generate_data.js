// portfolio-4-nosql/generate_data.js
// Bulk generator for MongoDB. Produces ~40,000+ documents across the three
// collections, with member/branch ids consistent with the PostgreSQL side.
// Run AFTER schema_validation.js.

function toNum(x) { return Number(x); }   // plain numbers: the schema accepts any BSON numeric type
db = db.getSiblingDB("ironcore_gym");

// Drop is done by schema_validation.js; this script just inserts.
const FIRST_NAMES = [
    "Chukwuemeka","Ngozi","Tunde","Aisha","Emeka","Fatima","Bola","Sani",
    "Yetunde","Kunle","Adaeze","Yakubu","Hauwa","Femi","Ifeoma","Musa",
    "Tari","Bashir","Ibrahim","Nneka","Olabisi","Uche","Wale","Zainab",
    "Adeola","Dauda","Ebere","Fatai","Hakeem","Jide","Kemi","Lola",
    "Mide","Nkechi","Obinna","Petra","Qudus","Rabi","Saheed","Tola"
];
const LAST_NAMES = [
    "Okafor","Bello","Adeyemi","Mohammed","Eze","Suleiman","Ogunleye","Abubakar",
    "Williams","Okeke","Audu","Olawale","Yusuf","Okoro","Idris","Ezeala",
    "Sanda","Gbenga","Balogun","Ibrahim","Nwosu","Ezeoke","Musa","Olatunji",
    "Adeleke","Sule","Okonkwo","Onuoha","Oluwatobi","Aminu","Dauda","Eze"
];
const BRANCH_IDS = [1,2,3,4,5];   // mirrors PostgreSQL branch_id 1..5
const STRENGTH = ["Bench press","Squat","Deadlift","Overhead press","Pull-up","Barbell row","Lunge","Leg press"];
const CARDIO   = ["Treadmill run","Cycling","Rowing","Stair climber","Battle ropes","Boxing skipping"];
const FLEX     = ["Hamstring stretch","Hip opener","Cobra pose","Pigeon pose","Cat-cow","Shoulder mobility"];

// 800 members (5,500 memberships in PostgreSQL — we mirror with the same range).
const MEMBER_COUNT = 800;
const TRAINER_COUNT = 10; // mirrors PostgreSQL trainer 1..10
const TOTAL_WORKOUTS = 42000;
const NOTES_PER_TRAINER = 200;
const MEAS_PER_MEMBER = 6;

// Bulk insert helpers — use insertMany in batches to keep memory low.
function randomDatePast(maxDays) {
    const d = new Date();
    d.setDate(d.getDate() - Math.floor(Math.random() * maxDays));
    d.setHours(6 + Math.floor(Math.random() * 14),
               Math.floor(Math.random() * 60), 0, 0);
    return d;
}
function randItem(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function randInt(lo, hi) { return Math.floor(Math.random() * (hi - lo + 1)) + lo; }
function randFloat(lo, hi, decimals) {
    const v = Math.random() * (hi - lo) + lo;
    const f = Math.pow(10, decimals || 2);
    return Math.round(v * f) / f;
}

print("Generating workouts in batches of 2,000...");
let workoutBatch = [];
let workoutId = 1;
for (let i = 0; i < TOTAL_WORKOUTS; i++) {
    const memberId = toNum(randInt(1, MEMBER_COUNT));
    const branchId = randInt(1, BRANCH_IDS.length);
    const trainerId = toNum(randInt(1, TRAINER_COUNT));
    const type = randItem(["strength","cardio","flexibility"]);
    const nExercises = randInt(2, 5);
    const exercises = [];
    for (let e = 0; e < nExercises; e++) {
        if (type === "strength") {
            exercises.push({
                name: randItem(STRENGTH),
                type: "strength",
                sets: randInt(3, 5),
                reps: randInt(6, 12),
                weight_kg: randFloat(10, 120, 1)
            });
        } else if (type === "cardio") {
            exercises.push({
                name: randItem(CARDIO),
                type: "cardio",
                distance_km: randFloat(0.5, 10, 2),
                duration_min: randInt(10, 60)
            });
        } else {
            exercises.push({
                name: randItem(FLEX),
                type: "flexibility",
                duration_min: randInt(10, 30),
                hold_sec: randInt(15, 60)
            });
        }
    }
    workoutBatch.push({
        workout_id: workoutId,
        member_id: memberId,
        branch_id: branchId,
        trainer_id: trainerId,
        date: randomDatePast(730),
        type: type,
        duration_min: randInt(30, 90),
        exercises: exercises,
        notes: "Auto-generated workout for portfolio demo.",
        created_at: new Date()
    });
    workoutId = workoutId + 1;

    if (workoutBatch.length >= 2000) {
        db.workouts.insertMany(workoutBatch, { ordered: false });
        workoutBatch = [];
    }
}
if (workoutBatch.length > 0) db.workouts.insertMany(workoutBatch, { ordered: false });
print("workouts inserted: " + db.workouts.estimatedDocumentCount());

// Trainer notes — 200 notes per trainer = 2,000 notes
print("Generating trainer_notes...");
let noteBatch = [];
let noteId = 1;
for (let t = 1; t <= TRAINER_COUNT; t++) {
    for (let n = 0; n < NOTES_PER_TRAINER; n++) {
        noteBatch.push({
            note_id: noteId,
            member_id: toNum(randInt(1, MEMBER_COUNT)),
            trainer_id: toNum(t),
            branch_id: randInt(1, BRANCH_IDS.length),
            date: randomDatePast(730),
            text: "Trainer " + t + " — focus on " + randItem(["form","breathing","hydration","pacing","recovery"]) +
                 ", member improving steadily.",
            tags: [randItem(["form","pace","hydration","recovery"])],
            created_at: new Date()
        });
        noteId = noteId + 1;
        if (noteBatch.length >= 500) {
            db.trainer_notes.insertMany(noteBatch, { ordered: false });
            noteBatch = [];
        }
    }
}
if (noteBatch.length > 0) db.trainer_notes.insertMany(noteBatch, { ordered: false });
print("trainer_notes inserted: " + db.trainer_notes.estimatedDocumentCount());

// Body measurements — 6 measurements per member over time = 4,800 measurements
print("Generating body_measurements...");
let measBatch = [];
for (let m = 1; m <= MEMBER_COUNT; m++) {
    let w = randFloat(60, 95, 1);
    let bf = randFloat(15, 35, 1);
    let waist = randFloat(70, 110, 1);
    for (let i = 0; i < MEAS_PER_MEMBER; i++) {
        // Each subsequent measurement drifts slightly.
        w = Math.max(45, w + randFloat(-1.5, 0.5, 1));
        bf = Math.max(8, bf + randFloat(-1, 0.4, 1));
        waist = Math.max(60, waist + randFloat(-1.2, 0.4, 1));
        measBatch.push({
            member_id: toNum(m),
            date: randomDatePast(730),
            weight_kg: w,
            body_fat_pct: bf,
            waist_cm: waist,
            bicep_cm: randFloat(28, 42, 1),
            chest_cm: randFloat(85, 115, 1),
            notes: "Auto-generated measurement."
        });
        if (measBatch.length >= 500) {
            db.body_measurements.insertMany(measBatch, { ordered: false });
            measBatch = [];
        }
    }
}
if (measBatch.length > 0) db.body_measurements.insertMany(measBatch, { ordered: false });
print("body_measurements inserted: " + db.body_measurements.estimatedDocumentCount());

print("");
print("== Portfolio 4 bulk load complete ==");
print("workouts total       : " + db.workouts.estimatedDocumentCount());
print("trainer_notes total  : " + db.trainer_notes.estimatedDocumentCount());
print("body_measurements tot: " + db.body_measurements.estimatedDocumentCount());
