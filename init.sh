#!/bin/bash

# Initialize database
/app/scripts/init-db.sh

# Start background scheduler
/app/scripts/scheduler.sh &

# Start shell2http server
exec shell2http -port 8080 \
    -export-all-vars \
    -form \
    / 'cat /app/frontend/index.html' \
    /api/register '/app/scripts/register.sh' \
    /api/status '/app/scripts/status.sh' \
    /api/worker '/app/scripts/worker.sh' \
    /api/stats '/app/scripts/stats.sh'
