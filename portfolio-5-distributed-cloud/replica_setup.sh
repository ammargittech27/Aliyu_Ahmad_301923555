#!/usr/bin/env bash
# portfolio-5-distributed-cloud/replica_setup.sh
# Builds a streaming read replica of the existing PostgreSQL 16 primary on
# port 5433. Codespaces-specific: uses Unix sockets, trust at top of pg_hba.conf,
# pg_ctl from /usr/lib/postgresql/16/bin, data dir chmod 700, copies of
# pg_hba.conf + pg_ident.conf, replica has its own postgresql.conf.
# Idempotent: re-running tears down the old replica and rebuilds.
set -euo pipefail

PG_BIN=/usr/lib/postgresql/16/bin
PG_CONF=/etc/postgresql/16/main
PRIMARY_DATA=/var/lib/postgresql/16/main
REPLICA_DATA=/var/lib/postgresql/16/replica
REPLICA_PORT=5433
REPL_USER=replicator
REPL_PASS=replpass
REPL_SLOT=ironcore_replica_slot

PSQL_PRIMARY="sudo runuser -u postgres -- psql -h /var/run/postgresql -d ironcore"

echo "==> [1/7] Configure primary for streaming replication"
$PSQL_PRIMARY <<SQL
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = '10';
ALTER SYSTEM SET max_replication_slots = '10';
ALTER SYSTEM SET listen_addresses = 'localhost';
SQL

echo "==> [2/7] Add trust replication line at the TOP of pg_hba.conf"
HBA="$PG_CONF/pg_hba.conf"
if ! sudo head -n 1 "$HBA" | grep -q '^local\s\+replication'; then
    sudo cp "$HBA" "${HBA}.bak.p5"
    { echo 'local   replication     all                                     trust'; \
      echo 'host    replication     all             127.0.0.1/32            trust'; \
      echo "host    replication     all             ::1/128                 trust"; \
      sudo cat "${HBA}.bak.p5"; } | sudo tee "$HBA" >/dev/null
fi

echo "==> [3/7] Restart primary so the new WAL & HBA settings take effect"
sudo pg_ctlcluster 16 main restart
sleep 2

echo "==> [4/7] Create replica role if it doesn't exist"
$PSQL_PRIMARY <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$REPL_USER') THEN
    CREATE ROLE $REPL_USER WITH REPLICATION LOGIN PASSWORD '$REPL_PASS';
  ELSE
    ALTER ROLE $REPL_USER WITH REPLICATION LOGIN PASSWORD '$REPL_PASS';
  END IF;
END
\$\$;
SQL

echo "==> [5/7] Stop existing replica (if any) and remove its data dir"
if sudo test -f "$REPLICA_DATA/postmaster.pid"; then
    sudo runuser -u postgres -- "$PG_BIN/pg_ctl" -D "$REPLICA_DATA" stop -m fast || true
fi
sudo rm -rf "$REPLICA_DATA"
sudo rm -f /tmp/pg_basebackup.log

$PSQL_PRIMARY -tAc "SELECT pg_drop_replication_slot('$REPL_SLOT') FROM pg_replication_slots WHERE slot_name='$REPL_SLOT' AND NOT active" >/dev/null || true
echo "==> [6/7] Base backup from primary into replica data dir (creates replication slot)"
sudo runuser -u postgres -- "$PG_BIN/pg_basebackup" \
    -h /var/run/postgresql -U "$REPL_USER" \
    -D "$REPLICA_DATA" -X stream -C -S "$REPL_SLOT" -P 2>&1 | tail -5

echo "==> [7/7] Configure replica: own postgresql.conf, copies of pg_hba/pg_ident, standby.signal"
# Own postgresql.conf for the replica (Codespaces rule)
sudo bash -c "cat > $REPLICA_DATA/postgresql.conf <<CONF
# Replica config (own file per Codespaces rule)
port = $REPLICA_PORT
listen_addresses = 'localhost'
hot_standby = on
hot_standby_feedback = on
primary_conninfo = 'host=/var/run/postgresql port=5432 user=$REPL_USER password=$REPL_PASS application_name=ironcore_replica'
CONF"

# Copies of pg_hba.conf and pg_ident.conf (Codespaces rule: replica needs its own)
sudo cp "$PG_CONF/pg_hba.conf" "$REPLICA_DATA/pg_hba.conf"
sudo cp "$PG_CONF/pg_ident.conf" "$REPLICA_DATA/pg_ident.conf"

# standby.signal marks the data dir as a standby
sudo bash -c "touch $REPLICA_DATA/standby.signal"

# Permissions must be 700 (Codespaces rule)
sudo chmod 700 "$REPLICA_DATA"
sudo chown -R postgres:postgres "$REPLICA_DATA"

# Start the replica
sudo runuser -u postgres -- "$PG_BIN/pg_ctl" -D "$REPLICA_DATA" -l /tmp/replica.log -w start

sleep 3

echo "==> Verification on PRIMARY:"
$PSQL_PRIMARY -c "SELECT application_name, state, sync_state, sent_lsn, write_lsn FROM pg_stat_replication;"

echo "==> Verification on REPLICA:"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p $REPLICA_PORT -d ironcore \
    -c "SELECT pg_is_in_recovery();"

echo "==> Done. Primary on /var/run/postgresql:5432 ; Replica on /var/run/postgresql:$REPLICA_PORT"
