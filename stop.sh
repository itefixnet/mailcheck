#!/bin/bash

# MailCheck - Docker Stop Script

CONTAINER_NAME="mailcheck"

echo "Stopping MailCheck container..."
docker stop "$CONTAINER_NAME"

if [ $? -eq 0 ]; then
    echo "Removing container..."
    docker rm "$CONTAINER_NAME"
    echo "✓ MailCheck stopped and removed"
else
    echo "Error: Failed to stop container (may not be running)"
    exit 1
fi
