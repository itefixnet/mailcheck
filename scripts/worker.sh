#!/bin/bash

DB_PATH="/app/data/mailcheck.db"
LOG_FILE="/app/data/mailcheck.log"
MAX_PARALLEL=${MAX_PARALLEL_CHECKS:-50}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to check mail server health (runs in background)
check_mail_server() {
    local domain=$1
    local email=$2
    local token=$3
    local previous_status=$4
    
    log "Checking mail server for domain: $domain (user: $email)"
    
    local status="ok"
    local errors=""
    
    # === DNS CHECKS ===
    
    # Check MX records
    MX_RECORDS=$(dig +short MX "$domain" 2>/dev/null | sort)
    if [[ -z "$MX_RECORDS" ]]; then
        status="error"
        errors="${errors}No MX records found. "
        MX_RECORDS="none"
    fi
    
    # Check SPF record
    SPF_RECORD=$(dig +short TXT "$domain" 2>/dev/null | grep -i "v=spf1" | head -1 | tr -d '"')
    if [[ -z "$SPF_RECORD" ]]; then
        SPF_RECORD="not found"
    fi
    
    # Check DMARC record
    DMARC_RECORD=$(dig +short TXT "_dmarc.$domain" 2>/dev/null | grep -i "v=DMARC1" | head -1 | tr -d '"')
    if [[ -z "$DMARC_RECORD" ]]; then
        DMARC_RECORD="not found"
    fi
    
    # DKIM - we can't check without knowing the selector, so just note it
    DKIM_STATUS="requires selector (not checked)"
    
    # === PORT CONNECTIVITY CHECKS ===
    
    # Get first MX server for port checks
    MX_HOST=$(echo "$MX_RECORDS" | head -1 | awk '{print $NF}' | sed 's/\.$//')
    
    if [[ -n "$MX_HOST" && "$MX_HOST" != "none" ]]; then
        # Check SMTP ports
        SMTP_25=$(timeout 5 bash -c "echo > /dev/tcp/$MX_HOST/25" 2>/dev/null && echo "open" || echo "closed")
        SMTP_587=$(timeout 5 bash -c "echo > /dev/tcp/$MX_HOST/587" 2>/dev/null && echo "open" || echo "closed")
        SMTP_465=$(timeout 5 bash -c "echo > /dev/tcp/$MX_HOST/465" 2>/dev/null && echo "open" || echo "closed")
        
        # Check IMAP/POP3 (use domain directly as these might be on different host)
        IMAP_993=$(timeout 5 bash -c "echo > /dev/tcp/$domain/993" 2>/dev/null && echo "open" || echo "closed")
        POP3_995=$(timeout 5 bash -c "echo > /dev/tcp/$domain/995" 2>/dev/null && echo "open" || echo "closed")
        
        if [[ "$SMTP_25" == "closed" && "$SMTP_587" == "closed" && "$SMTP_465" == "closed" ]]; then
            status="error"
            errors="${errors}No SMTP ports accessible. "
        fi
    else
        SMTP_25="n/a"
        SMTP_587="n/a"
        SMTP_465="n/a"
        IMAP_993="n/a"
        POP3_995="n/a"
    fi
    
    # === SSL/TLS CERTIFICATE CHECK ===
    
    SSL_VALID="unknown"
    SSL_EXPIRY=""
    SSL_DAYS=""
    
    if [[ -n "$MX_HOST" && "$MX_HOST" != "none" ]]; then
        # Try to get certificate from SMTP with STARTTLS
        CERT_INFO=$(echo | timeout 10 openssl s_client -connect "$MX_HOST:25" -starttls smtp -servername "$MX_HOST" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null)
        
        if [[ -n "$CERT_INFO" ]]; then
            SSL_VALID="valid"
            SSL_EXPIRY=$(echo "$CERT_INFO" | sed 's/notAfter=//')
            EXPIRY_EPOCH=$(date -d "$SSL_EXPIRY" +%s 2>/dev/null)
            NOW_EPOCH=$(date +%s)
            
            if [[ -n "$EXPIRY_EPOCH" ]]; then
                SSL_DAYS=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
                
                if [[ $SSL_DAYS -lt 30 && $SSL_DAYS -ge 0 ]]; then
                    status="warning"
                    errors="${errors}SSL certificate expires in $SSL_DAYS days. "
                elif [[ $SSL_DAYS -lt 0 ]]; then
                    status="error"
                    errors="${errors}SSL certificate expired ${SSL_DAYS#-} days ago. "
                fi
            fi
        else
            SSL_VALID="unavailable"
        fi
    fi
    
    # Escape single quotes for SQL
    MX_RECORDS=$(echo "$MX_RECORDS" | tr '\n' ';' | sed "s/'/''/g")
    SPF_RECORD=$(echo "$SPF_RECORD" | sed "s/'/''/g")
    DMARC_RECORD=$(echo "$DMARC_RECORD" | sed "s/'/''/g")
    errors=$(echo "$errors" | sed "s/'/''/g")
    SSL_EXPIRY=$(echo "$SSL_EXPIRY" | sed "s/'/''/g")
    
    # Update database
    sqlite3 "$DB_PATH" <<EOF
UPDATE mail_monitors SET 
    status='$status',
    last_check=datetime('now'),
    last_error='$errors',
    mx_records='$MX_RECORDS',
    spf_record='$SPF_RECORD',
    dkim_status='$DKIM_STATUS',
    dmarc_record='$DMARC_RECORD',
    smtp_port_25='$SMTP_25',
    smtp_port_587='$SMTP_587',
    smtp_port_465='$SMTP_465',
    imap_port_993='$IMAP_993',
    pop3_port_995='$POP3_995',
    smtp_ssl_valid='$SSL_VALID',
    smtp_ssl_expiry='$SSL_EXPIRY',
    smtp_ssl_days_remaining=$SSL_DAYS,
    error_count=CASE WHEN '$status'='error' THEN error_count+1 ELSE 0 END
WHERE token='$token';
EOF
    
    # Send email if status changed from ok to error/warning
    if [[ "$previous_status" == "ok" && "$status" != "ok" ]]; then
        send_alert "$email" "$domain" "$status" "$errors"
    fi
    
    log "Completed check for $domain - Status: $status"
}

# Function to send email alert
send_alert() {
    local email=$1
    local domain=$2
    local status=$3
    local errors=$4
    
    local subject="[MailCheck] Alert: $domain mail server is $status"
    local body="Your monitored mail server is experiencing issues:

Domain: $domain
Status: $status
Issues: $errors
Time: $(date '+%Y-%m-%d %H:%M:%S')

This is an automated alert from MailCheck monitoring service."
    
    echo "$body" | mail -s "$subject" "$email" 2>&1 | tee -a "$LOG_FILE"
    
    log "Alert sent to $email for $domain (Status: $status)"
}

# Main worker - processes monitors in parallel batches
log "Worker started - processing batch of up to $MAX_PARALLEL mail servers"

# Get all monitors that need checking (not checked in last 4 minutes)
MONITORS=$(sqlite3 "$DB_PATH" "SELECT domain, email, token, status FROM mail_monitors WHERE last_check IS NULL OR datetime(last_check, '+240 seconds') < datetime('now');")

if [[ -z "$MONITORS" ]]; then
    log "No mail servers need checking at this time"
    echo '{"status": "no_work", "message": "All monitors up to date"}'
    exit 0
fi

# Count total monitors
TOTAL=$(echo "$MONITORS" | wc -l)
log "Found $TOTAL mail servers to check"

# Process in parallel with limit
COUNTER=0
echo "$MONITORS" | while IFS='|' read -r domain email token status; do
    if [[ -n "$domain" && -n "$email" && -n "$token" ]]; then
        # Run check in background
        check_mail_server "$domain" "$email" "$token" "$status" &
        
        COUNTER=$((COUNTER + 1))
        
        # Limit parallel processes
        if [[ $((COUNTER % MAX_PARALLEL)) -eq 0 ]]; then
            wait  # Wait for current batch to complete
        fi
    fi
done

# Wait for remaining background jobs
wait

log "Worker completed - checked $TOTAL mail servers"

echo "{\"status\": \"success\", \"checked\": $TOTAL, \"max_parallel\": $MAX_PARALLEL}"
