FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    sqlite \
    wget \
    bind-tools \
    ca-certificates

# Install shell2http
RUN wget https://github.com/msoap/shell2http/releases/download/v1.16.0/shell2http_1.16.0_linux_amd64.tar.gz \
    && tar -xzf shell2http_1.16.0_linux_amd64.tar.gz \
    && mv shell2http /usr/local/bin/ \
    && rm shell2http_1.16.0_linux_amd64.tar.gz

# Create application directory
WORKDIR /app

# Copy application files
COPY scripts/ /app/scripts/
COPY frontend/ /app/frontend/
COPY init.sh /app/

# Create data directory for SQLite
RUN mkdir -p /app/data

# Make scripts executable
RUN chmod +x /app/scripts/*.sh /app/init.sh

# Expose port
EXPOSE 8080

# Start the application
CMD ["/app/init.sh"]
