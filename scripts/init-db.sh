#!/bin/bash

DB_PATH="/app/data/mailcheck.db"

# Create database and tables if they don't exist
sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS mail_monitors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL,
    domain TEXT NOT NULL,
    token TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_check DATETIME,
    status TEXT DEFAULT 'unknown',
    
    -- DNS checks
    mx_records TEXT,
    spf_record TEXT,
    dkim_status TEXT,
    dmarc_record TEXT,
    
    -- Connectivity checks
    smtp_port_25 TEXT DEFAULT 'unknown',
    smtp_port_587 TEXT DEFAULT 'unknown',
    smtp_port_465 TEXT DEFAULT 'unknown',
    imap_port_993 TEXT DEFAULT 'unknown',
    pop3_port_995 TEXT DEFAULT 'unknown',
    
    -- SSL/TLS checks
    smtp_ssl_valid TEXT DEFAULT 'unknown',
    smtp_ssl_expiry TEXT,
    smtp_ssl_days_remaining INTEGER,
    
    -- Errors
    last_error TEXT,
    error_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_token ON mail_monitors(token);
CREATE INDEX IF NOT EXISTS idx_email ON mail_monitors(email);
CREATE INDEX IF NOT EXISTS idx_domain ON mail_monitors(domain);
EOF

echo "Database initialized at $DB_PATH"
