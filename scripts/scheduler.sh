#!/bin/bash

# This script triggers the worker periodically

while true; do
    # Trigger worker via internal HTTP call
    curl -s http://localhost:8080/api/worker > /dev/null 2>&1
    
    # Sleep for 5 minutes (mail checks don't need to be as frequent)
    sleep 300
done
