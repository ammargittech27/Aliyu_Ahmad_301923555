#!/usr/bin/env bash
# portfolio-4-nosql/run_p4.sh
# 1. (re)create the three collections with strict $jsonSchema validation
# 2. bulk-load ~40,000 documents
# 3. run the 3+1 aggregations
# 4. demonstrate COLLSCAN -> IXSCAN by creating an index and re-explaining
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/4] Creating collections with \$jsonSchema validation"
mongosh --quiet --file "$DIR/schema_validation.js"

echo "==> [2/4] Generating bulk data (~42,000 workouts + 2,000 notes + 4,800 measurements)"
mongosh --quiet --file "$DIR/generate_data.js"

echo "==> [3/4] Running aggregations"
mongosh --quiet --file "$DIR/aggregations.js"

echo "==> [4/4] Index demo (COLLSCAN -> IXSCAN)"
mongosh --quiet --file "$DIR/create_index.js"

echo
echo "==> P4 complete. Copy the COLLSCAN vs IXSCAN summary from the output above"
echo "    into the comparison table in portfolio-4-nosql/README.md."
