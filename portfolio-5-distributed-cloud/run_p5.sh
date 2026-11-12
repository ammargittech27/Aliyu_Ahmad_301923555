#!/usr/bin/env bash
# portfolio-5-distributed-cloud/run_p5.sh
# 1. Rebuild class_booking as a monthly RANGE-partitioned table
# 2. Build the streaming read replica on port 5433
# 3. Run the replica demo (writes rejected, new rows replicated) in one psql script
#    using \connect to switch between primary and replica
set -euo pipefail

PSQL="sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -v ON_ERROR_STOP=1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/3] Rebuild class_booking as a monthly RANGE-partitioned table"
$PSQL -f "$DIR/partition.sql" 2>&1 | tee "$DIR/partition_output.log"

echo
echo "==> [2/3] Building the streaming read replica on port 5433"
bash "$DIR/replica_setup.sh"

echo
echo "==> [3/3] Running the replica demo (switches primary <-> replica with \\connect)"
# ON_ERROR_STOP off because the demo deliberately attempts writes that fail on the replica
(cd "$DIR" && sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore \
    -v ON_ERROR_STOP=0 -f "$DIR/replica_demo.sql") 2>&1 | tee "$DIR/replication_output.log"

echo
echo "==> P5 complete. Open portfolio-5-distributed-cloud/cloud_architecture.md"
echo "    for the NDPA 2023 design and the sync vs async / CAP discussion."
