#!/bin/bash

DB_PATH="/app/data/mailcheck.db"

# Get statistics
TOTAL_MONITORS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM mail_monitors;")
ACTIVE_CHECKS=$(ps aux | grep -c "[c]heck_mail_server")
LAST_WORKER_RUN=$(tail -1 /app/data/mailcheck.log 2>/dev/null | grep "Worker completed" || echo "Not yet run")

cat <<EOF
{
  "total_monitors": $TOTAL_MONITORS,
  "active_checks": $ACTIVE_CHECKS,
  "max_parallel": ${MAX_PARALLEL_CHECKS:-50},
  "last_worker_run": "$LAST_WORKER_RUN"
}
EOF
