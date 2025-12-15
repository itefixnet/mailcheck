FROM python:3.11-alpine

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    bind-tools \
    ca-certificates

# Install Python packages
RUN pip install --no-cache-dir aiohttp

# Create application directory
WORKDIR /app

# Copy application files
COPY scripts/ /app/scripts/
COPY frontend/ /app/frontend/
COPY server.py /app/

# Create data directory
RUN mkdir -p /app/data

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Expose port
EXPOSE 8080

# Start the application
CMD ["python3", "/app/server.py"]
