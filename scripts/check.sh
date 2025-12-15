#!/bin/bash

# Rate limiting with semaphore
MAX_CONCURRENT=${MAX_PARALLEL_CHECKS:-10}
LOCK_DIR="/tmp/mailcheck_locks"
mkdir -p "$LOCK_DIR"

# Count active checks
ACTIVE_CHECKS=$(find "$LOCK_DIR" -name 'check_*.lock' -mmin -2 2>/dev/null | wc -l)

if [[ $ACTIVE_CHECKS -ge $MAX_CONCURRENT ]]; then
    printf '{"error": "Server busy, please try again in a moment", "active_checks": %s}' "$ACTIVE_CHECKS"
    exit 1
fi

# Create lock file
LOCK_FILE="$LOCK_DIR/check_$$.lock"
touch "$LOCK_FILE"
trap "rm -f '$LOCK_FILE'" EXIT

# Get domain from v_domain variable (shell2http adds v_ prefix with -form flag)
DOMAIN="${v_v_domain}"

# URL decode the domain
DOMAIN=$(echo "$DOMAIN" | sed 's/%2F/\//g' | sed 's/%3A/:/g' | sed 's/%2E/./g' | sed 's/+/ /g')

# Basic validation
if [[ -z "$DOMAIN" ]]; then
    echo '{"error": "Domain is required"}'
    exit 1
fi

# Validate domain format
if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    echo '{"error": "Invalid domain format (e.g., example.com)"}'
    exit 1
fi

# Start total timer
START_TOTAL=$(date +%s%3N)

# === DNS CHECKS ===

# Check MX records
START_MX=$(date +%s%3N)
MX_RECORDS=$(timeout 5 dig +time=2 +tries=2 +short MX "$DOMAIN" 2>&1 | grep -E "^[0-9]+ " | sort)
TIME_MX=$(($(date +%s%3N) - START_MX))
if [[ -z "$MX_RECORDS" ]]; then
    MX_RECORDS="none"
    MX_STATUS="error"
else
    MX_STATUS="ok"
fi

# Check SPF record
START_SPF=$(date +%s%3N)
SPF_RECORD=$(timeout 5 dig +time=2 +tries=2 +short TXT "$DOMAIN" 2>&1 | grep -v "^;;" | grep -v "error" | grep -v "timed out" | grep -i "v=spf1" | head -1 | tr -d '"')
TIME_SPF=$(($(date +%s%3N) - START_SPF))
if [[ -z "$SPF_RECORD" ]]; then
    SPF_RECORD="not found"
    SPF_STATUS="warning"
else
    SPF_STATUS="ok"
fi

# Check DMARC record
START_DMARC=$(date +%s%3N)
DMARC_RECORD=$(timeout 5 dig +time=2 +tries=2 +short TXT "_dmarc.$DOMAIN" 2>&1 | grep -v "^;;" | grep -v "error" | grep -v "timed out" | grep -i "v=DMARC1" | head -1 | tr -d '"')
TIME_DMARC=$(($(date +%s%3N) - START_DMARC))
if [[ -z "$DMARC_RECORD" ]]; then
    DMARC_RECORD="not found"
    DMARC_STATUS="warning"
else
    DMARC_STATUS="ok"
fi

# === REPUTATION / BLACKLIST CHECKS ===

# Get first MX server for checks
MX_HOST=$(echo "$MX_RECORDS" | head -1 | awk '{print $NF}' | sed 's/\.$//')

# Get MX server IP address
if [[ -n "$MX_HOST" && "$MX_HOST" != "none" ]]; then
    MX_IP=$(timeout 5 dig +time=2 +tries=2 +short A "$MX_HOST" 2>&1 | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -1)
else
    MX_IP=""
fi

# Check against major RBLs
START_RBL=$(date +%s%3N)
RBL_LISTED=()
RBL_RESULTS=()
RBL_STATUS="ok"

if [[ -n "$MX_IP" ]]; then
    # Reverse IP for RBL queries
    REVERSED_IP=$(echo "$MX_IP" | awk -F. '{print $4"."$3"."$2"."$1}')
    
    # Get RBL list from environment or use defaults
    if [[ -n "$RBL_SERVERS" ]]; then
        IFS=',' read -ra RBLS <<< "$RBL_SERVERS"
    else
        RBLS=(
            "zen.spamhaus.org:Spamhaus"
            "bl.spamcop.net:SpamCop"
            "b.barracudacentral.org:Barracuda"
            "cbl.abuseat.org:CBL"
            "dnsbl-1.uceprotect.net:UCEPROTECT"
        )
    fi
    
    for rbl_entry in "${RBLS[@]}"; do
        RBL_HOST="${rbl_entry%%:*}"
        RBL_NAME="${rbl_entry##*:}"
        
        RBL_RESULT=$(timeout 3 dig +time=1 +tries=1 +short "$REVERSED_IP.$RBL_HOST" 2>/dev/null | head -1)
        
        # Valid blacklist response is 127.0.0.x (not NXDOMAIN or other IPs)
        if [[ -n "$RBL_RESULT" ]] && echo "$RBL_RESULT" | grep -qE "^127\.0\.0\.[0-9]+$"; then
            RBL_LISTED+=("$RBL_NAME")
            RBL_RESULTS+=("$RBL_NAME:listed")
            RBL_STATUS="error"
        else
            RBL_RESULTS+=("$RBL_NAME:clean")
        fi
    done
fi
TIME_RBL=$(($(date +%s%3N) - START_RBL))

if [[ ${#RBL_LISTED[@]} -eq 0 ]]; then
    RBL_MESSAGE="not listed on any blacklists"
    if [[ -z "$MX_IP" ]]; then
        RBL_MESSAGE="unable to check (no IP found)"
        RBL_STATUS="warning"
    fi
else
    RBL_MESSAGE="listed on: ${RBL_LISTED[*]}"
fi

# === PORT CONNECTIVITY CHECKS ===

START_PORTS=$(date +%s%3N)
if [[ -n "$MX_HOST" && "$MX_HOST" != "none" ]]; then
    # Check SMTP ports
    SMTP_25=$(timeout 5 bash -c "echo > /dev/tcp/$MX_HOST/25" 2>/dev/null && echo "open" || echo "closed")
    SMTP_587=$(timeout 5 bash -c "echo > /dev/tcp/$MX_HOST/587" 2>/dev/null && echo "open" || echo "closed")
    SMTP_465=$(timeout 5 bash -c "echo > /dev/tcp/$MX_HOST/465" 2>/dev/null && echo "open" || echo "closed")
    
    # Check IMAP/POP3 (use domain directly)
    IMAP_993=$(timeout 5 bash -c "echo > /dev/tcp/$DOMAIN/993" 2>/dev/null && echo "open" || echo "closed")
    POP3_995=$(timeout 5 bash -c "echo > /dev/tcp/$DOMAIN/995" 2>/dev/null && echo "open" || echo "closed")
else
    SMTP_25="n/a"
    SMTP_587="n/a"
    SMTP_465="n/a"
    IMAP_993="n/a"
    POP3_995="n/a"
fi
TIME_PORTS=$(($(date +%s%3N) - START_PORTS))

# === SSL/TLS CERTIFICATE CHECK ===

START_SSL=$(date +%s%3N)
SSL_VALID="unknown"
SSL_EXPIRY="n/a"
SSL_DAYS=0
SSL_STATUS="unknown"

if [[ -n "$MX_HOST" && "$MX_HOST" != "none" ]]; then
    # Try multiple ports to get certificate (587 STARTTLS, 465 direct SSL, 25 STARTTLS)
    CERT_INFO=""
    
    # Try port 587 with STARTTLS first (modern submission port)
    if [[ -z "$CERT_INFO" && "$SMTP_587" == "open" ]]; then
        CERT_INFO=$(echo | timeout 10 openssl s_client -connect "$MX_HOST:587" -starttls smtp -servername "$MX_HOST" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null)
    fi
    
    # Try port 465 with direct SSL/TLS
    if [[ -z "$CERT_INFO" && "$SMTP_465" == "open" ]]; then
        CERT_INFO=$(echo | timeout 10 openssl s_client -connect "$MX_HOST:465" -servername "$MX_HOST" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null)
    fi
    
    # Try port 25 with STARTTLS as fallback
    if [[ -z "$CERT_INFO" && "$SMTP_25" == "open" ]]; then
        CERT_INFO=$(echo | timeout 10 openssl s_client -connect "$MX_HOST:25" -starttls smtp -servername "$MX_HOST" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null)
    fi
    
    if [[ -n "$CERT_INFO" ]]; then
        SSL_VALID="valid"
        SSL_EXPIRY=$(echo "$CERT_INFO" | sed 's/notAfter=//')
        
        # Convert OpenSSL date format to epoch (BusyBox date compatible)
        # Format: "Mar 2 03:13:10 2026 GMT"
        MONTH=$(echo "$SSL_EXPIRY" | awk '{print $1}')
        DAY=$(echo "$SSL_EXPIRY" | awk '{print $2}')
        TIME=$(echo "$SSL_EXPIRY" | awk '{print $3}')
        YEAR=$(echo "$SSL_EXPIRY" | awk '{print $4}')
        
        # Convert month name to number
        case "$MONTH" in
            Jan) MONTH_NUM="01" ;;
            Feb) MONTH_NUM="02" ;;
            Mar) MONTH_NUM="03" ;;
            Apr) MONTH_NUM="04" ;;
            May) MONTH_NUM="05" ;;
            Jun) MONTH_NUM="06" ;;
            Jul) MONTH_NUM="07" ;;
            Aug) MONTH_NUM="08" ;;
            Sep) MONTH_NUM="09" ;;
            Oct) MONTH_NUM="10" ;;
            Nov) MONTH_NUM="11" ;;
            Dec) MONTH_NUM="12" ;;
            *) MONTH_NUM="01" ;;
        esac
        
        # Pad day with zero if needed
        DAY=$(printf "%02d" "$DAY")
        
        # Format: YYYYMMDDHHMMSS for BusyBox date
        DATE_STR="${YEAR}${MONTH_NUM}${DAY}${TIME//:/}"
        EXPIRY_EPOCH=$(date -D "%Y%m%d%H%M%S" -d "$DATE_STR" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        
        if [[ -n "$EXPIRY_EPOCH" ]]; then
            SSL_DAYS=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
            
            if [[ $SSL_DAYS -lt 30 && $SSL_DAYS -ge 0 ]]; then
                SSL_STATUS="warning"
            elif [[ $SSL_DAYS -lt 0 ]]; then
                SSL_STATUS="error"
            else
                SSL_STATUS="ok"
            fi
        else
            SSL_DAYS=0
        fi
    else
        SSL_VALID="unavailable"
        SSL_STATUS="warning"
        SSL_DAYS=0
    fi
fi
TIME_SSL=$(($(date +%s%3N) - START_SSL))

# === OPEN RELAY CHECK ===

START_RELAY=$(date +%s%3N)
RELAY_STATUS="unknown"
RELAY_MESSAGE="not tested"

if [[ -z "$MX_HOST" || "$MX_HOST" == "none" ]]; then
    RELAY_STATUS="n/a"
    RELAY_MESSAGE="no MX record found"
elif [[ "$SMTP_25" != "open" ]]; then
    RELAY_STATUS="warning"
    RELAY_MESSAGE="port 25 not accessible (may be blocked)"
else
    # Test if server accepts relay from external address
    RELAY_TEST=$(timeout 10 bash -c "
        exec 3<>/dev/tcp/$MX_HOST/25
        read -t 5 -u 3 banner
        echo 'HELO test.example.com' >&3
        read -t 5 -u 3 helo_resp
        echo 'MAIL FROM:<test@external.com>' >&3
        read -t 5 -u 3 mail_resp
        echo 'RCPT TO:<test@external.net>' >&3
        read -t 5 -u 3 rcpt_resp
        echo 'QUIT' >&3
        exec 3<&-
        exec 3>&-
        echo \"\$rcpt_resp\"
    " 2>/dev/null)
    
    if echo "$RELAY_TEST" | grep -qiE "^250|^2[0-9][0-9]"; then
        RELAY_STATUS="error"
        RELAY_MESSAGE="open relay detected - SECURITY RISK!"
    elif echo "$RELAY_TEST" | grep -qiE "^5[0-9][0-9]|relay|denied|rejected"; then
        RELAY_STATUS="ok"
        RELAY_MESSAGE="relay properly restricted"
    else
        RELAY_STATUS="unknown"
        RELAY_MESSAGE="unable to complete test"
    fi
fi
TIME_RELAY=$(($(date +%s%3N) - START_RELAY))

# Calculate total time
TIME_TOTAL=$(($(date +%s%3N) - START_TOTAL))

# Determine overall status
OVERALL_STATUS="ok"
if [[ "$MX_STATUS" == "error" ]] || [[ "$SSL_STATUS" == "error" ]] || [[ "$RELAY_STATUS" == "error" ]] || [[ "$RBL_STATUS" == "error" ]]; then
    OVERALL_STATUS="error"
elif [[ "$SPF_STATUS" == "warning" ]] || [[ "$DMARC_STATUS" == "warning" ]] || [[ "$SSL_STATUS" == "warning" ]] || [[ "$RBL_STATUS" == "warning" ]]; then
    OVERALL_STATUS="warning"
fi

# Escape for JSON
MX_RECORDS=$(echo "$MX_RECORDS" | tr '\n' ';' | sed 's/"/\\"/g')
SPF_RECORD=$(echo "$SPF_RECORD" | sed 's/"/\\"/g')
DMARC_RECORD=$(echo "$DMARC_RECORD" | sed 's/"/\\"/g')
SSL_EXPIRY=$(echo "$SSL_EXPIRY" | sed 's/"/\\"/g')
RBL_MESSAGE=$(echo "$RBL_MESSAGE" | sed 's/"/\\"/g')

# Build RBL results JSON array
RBL_RESULTS_JSON="["
for i in "${!RBL_RESULTS[@]}"; do
    RESULT="${RBL_RESULTS[$i]}"
    NAME="${RESULT%%:*}"
    STATUS="${RESULT##*:}"
    [[ $i -gt 0 ]] && RBL_RESULTS_JSON+=","
    RBL_RESULTS_JSON+="{\"name\":\"$NAME\",\"status\":\"$STATUS\"}"
done
RBL_RESULTS_JSON+="]"

# Output JSON (use printf to avoid trailing newlines)
printf '{
  "domain": "%s",
  "status": "%s",
  "checked_at": "%s",
  "mx_records": "%s",
  "mx_status": "%s",
  "mx_ip": "%s",
  "spf_record": "%s",
  "spf_status": "%s",
  "dmarc_record": "%s",
  "dmarc_status": "%s",
  "rbl_status": "%s",
  "rbl_message": "%s",
  "rbl_results": %s,
  "smtp_port_25": "%s",
  "smtp_port_587": "%s",
  "smtp_port_465": "%s",
  "imap_port_993": "%s",
  "pop3_port_995": "%s",
  "smtp_ssl_valid": "%s",
  "smtp_ssl_expiry": "%s",
  "smtp_ssl_days_remaining": %s,
  "smtp_ssl_status": "%s",
  "open_relay_status": "%s",
  "open_relay_message": "%s",
  "response_times": {
    "dns_ms": %s,
    "spf_ms": %s,
    "dmarc_ms": %s,
    "rbl_ms": %s,
    "ports_ms": %s,
    "ssl_ms": %s,
    "relay_ms": %s,
    "total_ms": %s
  }
}' "$DOMAIN" "$OVERALL_STATUS" "$(date '+%Y-%m-%d %H:%M:%S')" "$MX_RECORDS" "$MX_STATUS" "$MX_IP" "$SPF_RECORD" "$SPF_STATUS" "$DMARC_RECORD" "$DMARC_STATUS" "$RBL_STATUS" "$RBL_MESSAGE" "$RBL_RESULTS_JSON" "$SMTP_25" "$SMTP_587" "$SMTP_465" "$IMAP_993" "$POP3_995" "$SSL_VALID" "$SSL_EXPIRY" "$SSL_DAYS" "$SSL_STATUS" "$RELAY_STATUS" "$RELAY_MESSAGE" "$TIME_MX" "$TIME_SPF" "$TIME_DMARC" "$TIME_RBL" "$TIME_PORTS" "$TIME_SSL" "$TIME_RELAY" "$TIME_TOTAL"
