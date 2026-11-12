// portfolio-4-nosql/create_index.js
// Demonstrates COLLSCAN (no index) vs IXSCAN (with index) for a typical query.
// The query: "find all workouts for a given member_id, sorted by date desc".
// Run AFTER generate_data.js.
//
// MongoDB shows COLLSCAN in the winning plan when no index is used. After
// creating an index on (member_id, date), the winning plan becomes IXSCAN.

db = db.getSiblingDB("ironcore_gym");

// Drop the index if it already exists (idempotent).
try { db.workouts.dropIndex("idx_member_date"); } catch (e) {}

print("========================");
print("STEP 1 — Without index (COLLSCAN expected)");
print("Query: db.workouts.find({ member_id: 7 }).sort({ date: -1 }).limit(10)");
print("========================");
const before = db.workouts
    .find({ member_id: 7 })
    .sort({ date: -1 })
    .limit(10)
    .explain("executionStats");
print("  executionStats: nReturned=" + before.executionStats.nReturned + " docsExamined=" + before.executionStats.totalDocsExamined + " ms=" + before.executionStats.executionTimeMillis);

print("");
print("========================");
print("STEP 2 — Create compound index on (member_id, date)");
print("========================");
db.workouts.createIndex(
    { member_id: 1, date: -1 },
    { name: "idx_member_date" }
);
print("Index created: idx_member_date on (member_id: 1, date: -1)");

print("");
print("========================");
print("STEP 3 — With index (IXSCAN expected)");
print("Same query, same parameters");
print("========================");
const after = db.workouts
    .find({ member_id: 7 })
    .sort({ date: -1 })
    .limit(10)
    .explain("executionStats");
print("  executionStats: nReturned=" + after.executionStats.nReturned + " docsExamined=" + after.executionStats.totalDocsExamined + " ms=" + after.executionStats.executionTimeMillis);

print("");
print("========================");
print("STEP 4 — Summary comparison");
print("========================");

function stageKind(plan) {
    if (!plan) return "?";
    if (plan.stage === "IXSCAN") return "IXSCAN";
    if (plan.stage === "COLLSCAN") return "COLLSCAN";
    if (plan.inputStage) return stageKind(plan.inputStage);
    if (plan.inputStages) return stageKind(plan.inputStages[0]);
    return plan.stage || "?";
}

print("Before — winningPlan stage  : " + stageKind(before.queryPlanner.winningPlan));
print("Before — totalDocsExamined  : " + before.executionStats.totalDocsExamined);
print("Before — executionTimeMs    : " + before.executionStats.executionTimeMillis);
print("After  — winningPlan stage  : " + stageKind(after.queryPlanner.winningPlan));
print("After  — totalDocsExamined  : " + after.executionStats.totalDocsExamined);
print("After  — executionTimeMs    : " + after.executionStats.executionTimeMillis);

print("");
print("Real numbers above: copy them into the comparison table in portfolio-4-nosql/README.md.");
