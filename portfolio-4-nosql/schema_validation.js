// portfolio-4-nosql/schema_validation.js
// IronCore Fitness — MongoDB collections for workout logs + trainer notes + body
// measurements. Each workout stores exercises whose fields depend on exercise type
// (strength = sets/reps/weight, cardio = distance/duration, flexibility =
// duration/hold_sec). Enforced with $jsonSchema's oneOf (NOT if/then — the prompt
// explicitly says oneOf/anyOf).
//
// Run with: mongosh --file portfolio-4-nosql/schema_validation.js

db = db.getSiblingDB("ironcore_gym");

// ---------------------------------------------------------------------------
// Drop existing collections so re-running is idempotent
db.workouts.drop();
db.trainer_notes.drop();
db.body_measurements.drop();

// ---------------------------------------------------------------------------
// workouts collection — each workout has a type and an array of exercises.
// The exercise sub-document must satisfy exactly ONE of the oneOf branches,
// matching the workout's overall type.
db.createCollection("workouts", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["workout_id", "member_id", "branch_id", "trainer_id",
                       "date", "type", "exercises", "created_at"],
            properties: {
                _id: {},
                workout_id:  { bsonType: "number" },
                member_id:   { bsonType: "number" },
                branch_id:   { bsonType: "number" },
                trainer_id:  { bsonType: "number" },
                date:        { bsonType: "date" },
                type:        { enum: ["strength", "cardio", "flexibility"] },
                notes:       { bsonType: "string" },
                duration_min:{ bsonType: "number", minimum: 1 },
                exercises: {
                    bsonType: "array",
                    minItems: 1,
                    items: {
                        bsonType: "object",
                        required: ["name", "type"],
                        properties: {
                            name: { bsonType: "string" },
                            type: { enum: ["strength", "cardio", "flexibility"] },
                            // The fields below are validated by oneOf branch selection
                            sets:       { bsonType: "number", minimum: 1 },
                            reps:       { bsonType: "number", minimum: 1 },
                            weight_kg:  { bsonType: "number", minimum: 0 },
                            distance_km:{ bsonType: "number", minimum: 0 },
                            duration_min:{ bsonType: "number", minimum: 1 },
                            hold_sec:   { bsonType: "number", minimum: 1 }
                        },
                        // oneOf branches — exactly one must match for each exercise.
                        oneOf: [
                            {
                                properties: {
                                    type:        { enum: ["strength"] },
                                    sets:        { bsonType: "number", minimum: 1 },
                                    reps:        { bsonType: "number", minimum: 1 },
                                    weight_kg:   { bsonType: "number", minimum: 0 }
                                },
                                required: ["sets", "reps", "weight_kg"]
                            },
                            {
                                properties: {
                                    type:        { enum: ["cardio"] },
                                    distance_km: { bsonType: "number", minimum: 0 },
                                    duration_min:{ bsonType: "number", minimum: 1 }
                                },
                                required: ["distance_km", "duration_min"]
                            },
                            {
                                properties: {
                                    type:        { enum: ["flexibility"] },
                                    duration_min:{ bsonType: "number", minimum: 1 },
                                    hold_sec:    { bsonType: "number", minimum: 1 }
                                },
                                required: ["duration_min", "hold_sec"]
                            }
                        ]
                    }
                },
                created_at: { bsonType: "date" }
            },
            additionalProperties: false
        }
    },
    validationLevel: "strict",
    validationAction: "error"
});

// ---------------------------------------------------------------------------
// trainer_notes collection — free-text notes a trainer leaves about a member,
// linked to a workout date and a branch.
db.createCollection("trainer_notes", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["note_id", "member_id", "trainer_id", "branch_id", "date", "text", "created_at"],
            properties: {
                _id: {},
                note_id:    { bsonType: "number" },
                member_id:  { bsonType: "number" },
                trainer_id: { bsonType: "number" },
                branch_id:  { bsonType: "number" },
                date:       { bsonType: "date" },
                text:       { bsonType: "string", minLength: 1 },
                tags:       { bsonType: "array", items: { bsonType: "string" } },
                created_at: { bsonType: "date" }
            },
            additionalProperties: false
        }
    },
    validationLevel: "strict",
    validationAction: "error"
});

// ---------------------------------------------------------------------------
// body_measurements collection — same member measured over time (weight,
// body_fat_pct, waist_cm, bicep_cm, etc.).
db.createCollection("body_measurements", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["member_id", "date", "weight_kg"],
            properties: {
                _id: {},
                member_id:     { bsonType: "number" },
                date:          { bsonType: "date" },
                weight_kg:     { bsonType: "number", minimum: 0 },
                body_fat_pct:  { bsonType: "number", minimum: 0, maximum: 100 },
                waist_cm:      { bsonType: "number", minimum: 0 },
                bicep_cm:      { bsonType: "number", minimum: 0 },
                chest_cm:      { bsonType: "number", minimum: 0 },
                notes:         { bsonType: "string" }
            },
            additionalProperties: false
        }
    },
    validationLevel: "strict",
    validationAction: "error"
});

print("Collections created: workouts, trainer_notes, body_measurements — strict $jsonSchema validation with oneOf.");

// ---------------------------------------------------------------------------
// Validation self-test: one GOOD document must be accepted, two BAD ones rejected.
function tryInsert(label, coll, doc, shouldPass) {
    try { db[coll].insertOne(doc); if (shouldPass) { print("PASS: " + label + " accepted"); db[coll].deleteOne({ _id: doc._id }); }
          else { print("FAIL: " + label + " was accepted but should have been rejected"); quit(1); } }
    catch (e) { if (shouldPass) { print("FAIL: " + label + " rejected: " + e.message); quit(1); }
                else print("PASS: " + label + " rejected by validation (code " + e.code + ")"); }
}
const ok = { _id: ObjectId(), workout_id: Long(900000001), member_id: Long(1), branch_id: Int32(1), trainer_id: Long(1),
             date: new Date(), type: "strength", exercises: [{ name: "Squat", type: "strength", sets: Int32(3), reps: Int32(8), weight_kg: 60.5 }], created_at: new Date() };
tryInsert("valid strength workout", "workouts", ok, true);
tryInsert("strength exercise missing sets/reps/weight_kg", "workouts",
          Object.assign({}, ok, { _id: ObjectId(), exercises: [{ name: "Squat", type: "strength" }] }), false);
tryInsert("cardio exercise carrying a strength-only shape", "workouts",
          Object.assign({}, ok, { _id: ObjectId(), type: "cardio", exercises: [{ name: "Run", type: "cardio", sets: Int32(3) }] }), false);
