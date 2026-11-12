#!/usr/bin/env bash
# setup.sh — Codespaces / Ubuntu 24.04 bootstrap for IronCore Fitness portfolio.
# Installs PostgreSQL 16 and MongoDB 8, starts both services, creates the
# ironcore PostgreSQL database and the ironcore_gym MongoDB database.
set -euo pipefail

echo "==> [1/9] Removing stale yarn apt source (conflicts with apt-get update)"
sudo rm -f /etc/apt/sources.list.d/yarn.list || true

echo "==> [2/9] apt-get update"
sudo apt-get update -qq

echo "==> [3/9] Installing PostgreSQL 16 (and contrib for btree_gist)"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    postgresql postgresql-contrib postgresql-client-16

echo "==> [4/9] Installing MongoDB 8.0 (official repo)"
# Import MongoDB public GPG key and add the repo for Ubuntu 22.04 (jammy) — compatible with Codespaces base image.
if ! command -v mongod >/dev/null 2>&1; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
    CODENAME="$(. /etc/os-release; echo "$VERSION_CODENAME")"
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $CODENAME/mongodb-org/8.0 multiverse" \
        | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mongodb-org
fi

echo "==> [5/9] Starting PostgreSQL 16"
sudo pg_ctlcluster 16 main start || sudo systemctl start postgresql

echo "==> [6/9] Ensuring Unix-socket trust auth (place at TOP of pg_hba.conf)"
HBA=/etc/postgresql/16/main/pg_hba.conf
if ! sudo head -n 1 "$HBA" | grep -q '^local\s\+all\s\+all\s\+trust'; then
    sudo cp "$HBA" "${HBA}.bak"
    { echo 'local   all             all                                     trust'; echo 'local   replication     all                                     trust'; sudo cat "${HBA}.bak"; } | sudo tee "$HBA" >/dev/null
fi
sudo pg_ctlcluster 16 main restart

echo "==> [7/9] Creating PostgreSQL database 'ironcore' (idempotent)"
sudo runuser -u postgres -- psql -h /var/run/postgresql -tAc "SELECT 1 FROM pg_database WHERE datname='ironcore'" \
    | grep -q 1 || sudo runuser -u postgres -- createdb -h /var/run/postgresql ironcore
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -c "CREATE EXTENSION IF NOT EXISTS btree_gist;" >/dev/null
sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore -c "ALTER DATABASE ironcore SET timezone TO 'Africa/Lagos';" >/dev/null

echo "==> [8/9] Starting MongoDB and creating 'ironcore_gym' database (idempotent)"
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R mongodb:mongodb /data/db /var/log/mongodb
pgrep -x mongod >/dev/null || sudo runuser -u mongodb -- /usr/bin/mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null
for i in $(seq 1 20); do mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1 && break; sleep 1; done
mongosh --quiet --eval 'db = db.getSiblingDB("ironcore_gym"); db.init.findOne({x:1});' || true

echo "==> [9/9] psycopg2 for the P3 race demos (fallback chain, then verify)"
python3 -c 'import psycopg2' 2>/dev/null || pip install psycopg2-binary 2>/dev/null || pip install --user psycopg2-binary 2>/dev/null \
  || pip install --break-system-packages psycopg2-binary 2>/dev/null || pip install --user --break-system-packages psycopg2-binary 2>/dev/null \
  || sudo apt-get install -y -qq python3-psycopg2 || true
python3 -c 'import psycopg2; print("psycopg2 OK", psycopg2.__version__)'

echo
echo "==> Setup complete."
echo "    PostgreSQL 16 : database 'ironcore', Unix socket /var/run/postgresql"
echo "    MongoDB 8     : database 'ironcore_gym', localhost:27017"
echo
echo "Next steps:"
echo "  bash portfolio-1-database-design/run_p1.sh"
echo "  bash portfolio-2-query-optimisation/run_p2.sh"
echo "  bash portfolio-3-transactions-concurrency/run_p3.sh"
echo "  bash portfolio-4-nosql/run_p4.sh"
echo "  bash portfolio-5-distributed-cloud/run_p5.sh"
