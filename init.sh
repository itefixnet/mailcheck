#!/bin/bash

# Start shell2http server
exec shell2http -port 8080 \
    -export-all-vars \
    -form \
    / 'cat /app/frontend/index.html' \
    /api/check 'bash -c /app/scripts/check.sh'
