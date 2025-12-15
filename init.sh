#!/bin/bash

# MailCheck - Docker Initialization Script

IMAGE_NAME="mailcheck:latest"
CONTAINER_NAME="mailcheck"
PORT="${PORT:-8080}"

echo "Building MailCheck Docker image..."
docker build -t "$IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi

echo "Stopping and removing existing container if present..."
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null

echo "Starting MailCheck container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "$PORT:8080" \
  -e DKIM_SELECTORS="${DKIM_SELECTORS:-default,selector1,selector2,google,k1,dkim,s1,s2,mail,email}" \
  -e RBL_SERVERS="${RBL_SERVERS:-zen.spamhaus.org:Spamhaus,bl.spamcop.net:SpamCop,b.barracudacentral.org:Barracuda,cbl.abuseat.org:CBL,dnsbl-1.uceprotect.net:UCEPROTECT}" \
  -e DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,1.1.1.1}" \
  "$IMAGE_NAME"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ MailCheck is running!"
    echo ""
    echo "  URL: http://localhost:$PORT"
    echo "  Container: $CONTAINER_NAME"
    echo ""
    echo "View logs: docker logs -f $CONTAINER_NAME"
    echo "Stop: ./stop.sh"
    echo ""
else
    echo "Error: Failed to start container"
    exit 1
fi
