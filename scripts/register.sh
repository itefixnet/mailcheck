#!/bin/bash

DB_PATH="/app/data/mailcheck.db"

# Read POST data
read -r POST_DATA

# Parse email and domain from POST data
EMAIL=$(echo "$POST_DATA" | sed -n 's/.*email=\([^&]*\).*/\1/p' | sed 's/%40/@/g' | sed 's/%3A/:/g' | sed 's/%2F/\//g')
DOMAIN=$(echo "$POST_DATA" | sed -n 's/.*domain=\([^&]*\).*/\1/p' | sed 's/%2F/\//g' | sed 's/%3A/:/g')

# Basic validation
if [[ -z "$EMAIL" || -z "$DOMAIN" ]]; then
    echo '{"error": "Email and domain are required"}'
    exit 1
fi

# Validate email format
if ! echo "$EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    echo '{"error": "Invalid email format"}'
    exit 1
fi

# Validate domain format
if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    echo '{"error": "Invalid domain format (e.g., example.com)"}'
    exit 1
fi

# Check if email already has a monitor
EXISTING_TOKEN=$(sqlite3 "$DB_PATH" "SELECT token FROM mail_monitors WHERE email='$EMAIL' LIMIT 1;")

if [[ -n "$EXISTING_TOKEN" ]]; then
    echo "{\"token\": \"$EXISTING_TOKEN\", \"message\": \"Email already registered. Use this token to check status.\"}"
    exit 0
fi

# Generate unique token
TOKEN=$(openssl rand -hex 16)

# Insert into database
sqlite3 "$DB_PATH" "INSERT INTO mail_monitors (email, domain, token) VALUES ('$EMAIL', '$DOMAIN', '$TOKEN');"

if [[ $? -eq 0 ]]; then
    echo "{\"token\": \"$TOKEN\", \"message\": \"Successfully registered. Mail server health check will start within 5 minutes.\"}"
else
    echo '{"error": "Failed to register monitor"}'
    exit 1
fi
