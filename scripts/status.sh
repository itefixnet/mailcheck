#!/bin/bash

DB_PATH="/app/data/mailcheck.db"

# Get token from query string
TOKEN=$(echo "$QUERY_STRING" | sed -n 's/.*token=\([^&]*\).*/\1/p')

if [[ -z "$TOKEN" ]]; then
    echo '{"error": "Token is required"}'
    exit 1
fi

# Query monitor status
RESULT=$(sqlite3 -json "$DB_PATH" "SELECT 
    email, domain, status, last_check, last_error,
    mx_records, spf_record, dkim_status, dmarc_record,
    smtp_port_25, smtp_port_587, smtp_port_465,
    imap_port_993, pop3_port_995,
    smtp_ssl_valid, smtp_ssl_expiry, smtp_ssl_days_remaining,
    error_count
FROM mail_monitors WHERE token='$TOKEN' LIMIT 1;")

if [[ -z "$RESULT" || "$RESULT" == "[]" ]]; then
    echo '{"error": "Invalid token"}'
    exit 1
fi

echo "$RESULT"
