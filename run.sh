#!/bin/bash

# Build the image
docker build -t mailcheck:latest .

# Stop and remove existing container if it exists
docker stop mailcheck 2>/dev/null
docker rm mailcheck 2>/dev/null

# Run the container
    docker run -d \
  --name mailcheck \
  --restart unless-stopped \
  -p 8080:8080 \
  -v "$(pwd)/data:/app/data" \
  -e MAX_PARALLEL_CHECKS="${MAX_PARALLEL_CHECKS:-10}" \
  -e RBL_SERVERS="${RBL_SERVERS:-zen.spamhaus.org:Spamhaus,bl.spamcop.net:SpamCop,b.barracudacentral.org:Barracuda,cbl.abuseat.org:CBL,dnsbl-1.uceprotect.net:UCEPROTECT}" \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  mailcheck:latestecho "MailCheck is running at http://localhost:8080"
docker logs -f mailcheck
