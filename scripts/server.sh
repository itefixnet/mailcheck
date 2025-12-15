#!/bin/bash

# Simple web server using socat
# Handles HTTP requests and serves files or executes scripts

PORT="${PORT:-8080}"
FRONTEND_DIR="/app/frontend"
SCRIPTS_DIR="/app/scripts"

handle_request() {
    # Read HTTP request
    read -r REQUEST_LINE
    METHOD=$(echo "$REQUEST_LINE" | cut -d' ' -f1)
    URI=$(echo "$REQUEST_LINE" | cut -d' ' -f2)
    
    # Read headers until empty line
    while read -r HEADER && [ -n "$HEADER" ] && [ "$HEADER" != $'\r' ]; do
        HEADER_NAME=$(echo "$HEADER" | cut -d: -f1 | tr '[:upper:]' '[:lower:]' | tr -d '\r')
        HEADER_VALUE=$(echo "$HEADER" | cut -d: -f2- | sed 's/^ *//' | tr -d '\r')
        
        case "$HEADER_NAME" in
            content-length) CONTENT_LENGTH="$HEADER_VALUE" ;;
            content-type) CONTENT_TYPE="$HEADER_VALUE" ;;
        esac
    done
    
    # Read POST body if present
    POST_DATA=""
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
        POST_DATA=$(head -c "$CONTENT_LENGTH")
    fi
    
    # Route requests
    case "$URI" in
        /)
            # Serve index.html
            if [ -f "$FRONTEND_DIR/index.html" ]; then
                FILE_SIZE=$(wc -c < "$FRONTEND_DIR/index.html")
                echo -ne "HTTP/1.1 200 OK\r\n"
                echo -ne "Content-Type: text/html\r\n"
                echo -ne "Content-Length: $FILE_SIZE\r\n"
                echo -ne "Connection: close\r\n"
                echo -ne "\r\n"
                cat "$FRONTEND_DIR/index.html"
            else
                echo -ne "HTTP/1.1 404 Not Found\r\n"
                echo -ne "Content-Type: text/plain\r\n"
                echo -ne "Connection: close\r\n"
                echo -ne "\r\n"
                echo "404 Not Found"
            fi
            ;;
            
        /check)
            # Handle mail server check
            if [ "$METHOD" = "POST" ]; then
                # URL decode helper function
                urldecode() {
                    echo "$1" | sed 's/%2E/./g; s/%2C/,/g; s/%3A/:/g; s/+/ /g; s/%20/ /g; s/%2F/\//g'
                }
                
                # Extract parameters from POST data using sed (POSIX compatible)
                DOMAIN=$(echo "$POST_DATA" | sed -n 's/.*domain=\([^&]*\).*/\1/p' | head -1)
                DOMAIN=$(urldecode "$DOMAIN")
                
                DKIM_SEL=$(echo "$POST_DATA" | sed -n 's/.*dkim_selectors=\([^&]*\).*/\1/p' | head -1)
                DKIM_SEL=$(urldecode "$DKIM_SEL")
                
                RBL_SRV=$(echo "$POST_DATA" | sed -n 's/.*rbl_servers=\([^&]*\).*/\1/p' | head -1)
                RBL_SRV=$(urldecode "$RBL_SRV")
                
                DNS_SRV=$(echo "$POST_DATA" | sed -n 's/.*dns_servers=\([^&]*\).*/\1/p' | head -1)
                DNS_SRV=$(urldecode "$DNS_SRV")
                
                if [ -z "$DOMAIN" ]; then
                    echo -ne "HTTP/1.1 400 Bad Request\r\n"
                    echo -ne "Content-Type: application/json\r\n"
                    echo -ne "Connection: close\r\n"
                    echo -ne "\r\n"
                    echo '{"error":"Domain is required"}'
                else
                    # Run check script with properly quoted environment variables
                    RESULT=$(v_v_domain="$DOMAIN" DKIM_SELECTORS="$DKIM_SEL" RBL_SERVERS="$RBL_SRV" DNS_SERVERS="$DNS_SRV" "$SCRIPTS_DIR/check.sh" 2>&1)
                    RESULT_SIZE=${#RESULT}
                    
                    echo -ne "HTTP/1.1 200 OK\r\n"
                    echo -ne "Content-Type: application/json\r\n"
                    echo -ne "Content-Length: $RESULT_SIZE\r\n"
                    echo -ne "Connection: close\r\n"
                    echo -ne "\r\n"
                    echo -n "$RESULT"
                fi
            else
                echo -ne "HTTP/1.1 405 Method Not Allowed\r\n"
                echo -ne "Content-Type: text/plain\r\n"
                echo -ne "Connection: close\r\n"
                echo -ne "\r\n"
                echo "405 Method Not Allowed"
            fi
            ;;
            
        /health)
            # Health check endpoint
            RESPONSE='{"status":"ok"}'
            RESPONSE_SIZE=${#RESPONSE}
            echo -ne "HTTP/1.1 200 OK\r\n"
            echo -ne "Content-Type: application/json\r\n"
            echo -ne "Content-Length: $RESPONSE_SIZE\r\n"
            echo -ne "Connection: close\r\n"
            echo -ne "\r\n"
            echo -n "$RESPONSE"
            ;;
            
        *)
            # 404 for everything else
            echo -ne "HTTP/1.1 404 Not Found\r\n"
            echo -ne "Content-Type: text/plain\r\n"
            echo -ne "Connection: close\r\n"
            echo -ne "\r\n"
            echo "404 Not Found"
            ;;
    esac
}

# Export function for subshells
export -f handle_request
export FRONTEND_DIR SCRIPTS_DIR

echo "Starting socat web server on port $PORT..."

# Run socat server
socat TCP-LISTEN:$PORT,reuseaddr,fork SYSTEM:'bash -c handle_request'
