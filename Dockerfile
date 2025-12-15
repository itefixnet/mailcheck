FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    bash \
    socat \
    curl \
    openssl \
    bind-tools \
    ca-certificates \
    netcat-openbsd

# Create application directory
WORKDIR /app

# Copy application files
COPY scripts/ /app/scripts/
COPY frontend/ /app/frontend/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Create non-root user
RUN addgroup -g 1000 mailcheck && \
    adduser -D -u 1000 -G mailcheck mailcheck && \
    chown -R mailcheck:mailcheck /app

# Switch to non-root user
USER mailcheck

# Expose port
EXPOSE 8080

# Start the application
CMD ["/app/scripts/server.sh"]
