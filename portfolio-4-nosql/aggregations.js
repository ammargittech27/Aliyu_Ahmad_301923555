// portfolio-4-nosql/aggregations.js
// Three aggregations across the three collections:
//   1. Most popular exercises (across all workouts, all branches)
//   2. Average progress per member (weight trend from body_measurements)
//   3. Trainer notes per branch (count + sample)
// Run AFTER generate_data.js.

db = db.getSiblingDB("ironcore_gym");

print("========================");
print("Aggregation 1: Most popular exercises");
print("(unwind exercises array, group by name + type, sort by count desc)");
print("========================");
const popular = db.workouts.aggregate([
    { $unwind: "$exercises" },
    { $group: {
        _id: { name: "$exercises.name", type: "$exercises.type" },
        sessions: { $sum: 1 },
        avg_weight_kg: { $avg: "$exercises.weight_kg" },
        avg_distance_km: { $avg: "$exercises.distance_km" },
        avg_duration_min: { $avg: "$exercises.duration_min" }
    }},
    { $sort: { sessions: -1 } },
    { $limit: 15 }
]).toArray();
printjson(popular);

print("");
print("========================");
print("Aggregation 2: Average progress per member (weight delta from first to last measurement)");
print("========================");
const progress = db.body_measurements.aggregate([
    { $sort: { member_id: 1, date: 1 } },
    { $group: {
        _id: "$member_id",
        first_weight: { $first: "$weight_kg" },
        last_weight: { $last: "$weight_kg" },
        first_date: { $first: "$date" },
        last_date: { $last: "$date" },
        measurements: { $sum: 1 }
    }},
    { $addFields: {
        weight_delta_kg: { $round: [{ $subtract: ["$last_weight", "$first_weight"] }, 2] }
    }},
    { $sort: { weight_delta_kg: 1 } },
    { $limit: 10 }
]).toArray();
printjson(progress);

print("");
print("========================");
print("Aggregation 3: Trainer notes per branch");
print("========================");
const notesByBranch = db.trainer_notes.aggregate([
    { $group: {
        _id: "$branch_id",
        note_count: { $sum: 1 },
        distinct_trainers: { $addToSet: "$trainer_id" },
        sample_notes: { $push: "$text" }
    }},
    { $addFields: {
        distinct_trainer_count: { $size: "$distinct_trainers" },
        first_3_notes: { $slice: ["$sample_notes", 3] }
    }},
    { $project: { distinct_trainers: 0, sample_notes: 0 } },
    { $sort: { note_count: -1 } }
]).toArray();
printjson(notesByBranch);

print("");
print("========================");
print("Bonus aggregation 4: Most popular exercise per branch");
print("========================");
const perBranch = db.workouts.aggregate([
    { $unwind: "$exercises" },
    { $group: {
        _id: { branch_id: "$branch_id", name: "$exercises.name" },
        sessions: { $sum: 1 }
    }},
    { $sort: { "_id.branch_id": 1, sessions: -1 } },
    { $group: {
        _id: "$_id.branch_id",
        top_exercise: { $first: "$_id.name" },
        top_count: { $first: "$sessions" }
    }},
    { $sort: { _id: 1 } }
]).toArray();
printjson(perBranch);
