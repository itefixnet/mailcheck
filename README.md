# MailCheck - Mail Server Health Monitoring

A minimal, dockerized mail server health monitoring service built with shell2http and bash scripts.

## Features

- 📧 **MX Records Check** - Verifies mail server configuration
- 🔒 **SSL/TLS Certificate Monitoring** - Checks SMTP certificate validity and expiration
- 🌐 **DNS Records** - Validates SPF, DKIM, and DMARC records
- 🔌 **Port Connectivity** - Tests SMTP (25, 587, 465), IMAP (993), POP3 (995)
- 📊 **Simple Web Interface** - Easy monitoring dashboard
- ⚡ **Parallel Worker Architecture** - Check up to 50 mail servers concurrently
- 🔄 **No Cron Dependencies** - Pure shell2http event-driven
- 📬 **Email Alerts** - Notifications when issues are detected

## Quick Start

### Prerequisites

- Docker and Docker Compose
- SMTP server for sending alert emails (optional but recommended)

### Setup

1. Clone this repository:
```bash
git clone <your-repo>
cd monpleto
```

2. Build and run:
```bash
docker-compose up -d
```

3. Access the web interface:
```
http://localhost:8080
```

## What It Checks

### DNS Records
- **MX Records** - Mail server addresses
- **SPF Record** - Sender Policy Framework for anti-spoofing
- **DMARC Record** - Domain-based Message Authentication
- **DKIM Status** - DomainKeys Identified Mail (requires selector)

### Port Connectivity
- **Port 25** - Standard SMTP
- **Port 587** - SMTP Submission (recommended)
- **Port 465** - SMTP over SSL (legacy)
- **Port 993** - IMAP over SSL
- **Port 995** - POP3 over SSL

### SSL/TLS Certificates
- Certificate validity
- Expiration date and days remaining
- Warnings at 30 days before expiry

## Configuration

### Parallel Workers

By default, the system can run up to 50 parallel mail server checks. Configure via environment variable:

```yaml
environment:
  - MAX_PARALLEL_CHECKS=100  # Increase to 100 concurrent checks
```

### Email Alerts

Configure SMTP settings for sending alerts:

```yaml
environment:
  - SMTP_HOST=smtp.gmail.com
  - SMTP_PORT=587
```

### Check Frequency

Mail servers are checked every 5 minutes by default. Modify in `scripts/scheduler.sh`:
```bash
sleep 300  # 300 seconds = 5 minutes
```

## Usage

### Register a Mail Server

1. Visit http://localhost:8080
2. Enter your email address (for receiving alerts)
3. Enter the mail server domain (e.g., `gmail.com` or `yourdomain.com`)
4. Click "Start Monitoring"
5. Save the token provided

### Check Status

1. Enter your token in the "Check Status" section
2. Click "Check Status"
3. View comprehensive health report including:
   - DNS records status
   - Port availability
   - SSL certificate details
   - Any detected issues

## API Endpoints

### POST /api/register
Register a new mail server monitor.

**Parameters:**
- `email` - Email address for alerts
- `domain` - Mail server domain to monitor

**Response:**
```json
{
  "token": "abc123...",
  "message": "Successfully registered"
}
```

### GET /api/status?token=TOKEN
Get mail server health status.

**Response:**
```json
[{
  "email": "user@example.com",
  "domain": "example.com",
  "status": "ok",
  "last_check": "2025-12-15 12:34:56",
  "mx_records": "10 mail.example.com.",
  "spf_record": "v=spf1 include:_spf.example.com ~all",
  "dmarc_record": "v=DMARC1; p=quarantine",
  "smtp_port_25": "open",
  "smtp_port_587": "open",
  "smtp_port_465": "closed",
  "imap_port_993": "open",
  "pop3_port_995": "closed",
  "smtp_ssl_valid": "valid",
  "smtp_ssl_expiry": "Jan 1 00:00:00 2026 GMT",
  "smtp_ssl_days_remaining": 382,
  "last_error": "",
  "error_count": 0
}]
```

### GET /api/worker
Manually trigger health checks for all pending monitors.

**Response:**
```json
{
  "status": "success",
  "checked": 42,
  "max_parallel": 50
}
```

### GET /api/stats
Get system statistics.

**Response:**
```json
{
  "total_monitors": 42,
  "active_checks": 5,
  "max_parallel": 50,
  "last_worker_run": "[2025-12-15 12:34:56] Worker completed"
}
```

## Monitoring Logic

- Background scheduler triggers worker every 5 minutes
- Worker spawns parallel check processes (configurable, default 50)
- Each check performs:
  1. DNS lookups (MX, SPF, DMARC)
  2. Port connectivity tests
  3. SSL certificate validation
  4. Database update with results
- Email alerts sent when status changes from OK to ERROR/WARNING
- Checks only run if last check was >4 minutes ago (prevents overlaps)

## Project Structure

```
monpleto/
├── Dockerfile              # Container definition
├── docker-compose.yml      # Docker Compose configuration
├── init.sh                 # Container startup script
├── scripts/
│   ├── init-db.sh         # Database initialization
│   ├── register.sh        # Registration endpoint
│   ├── status.sh          # Status endpoint
│   ├── worker.sh          # Parallel mail health checker
│   ├── scheduler.sh       # Background scheduler
│   └── stats.sh           # Statistics endpoint
├── frontend/
│   └── index.html         # Web interface
└── data/                  # SQLite database (created at runtime)
```

## Development

### Building locally
```bash
docker build -t mailcheck .
```

### Running without Docker Compose
```bash
docker run -p 8080:8080 -v $(pwd)/data:/app/data mailcheck
```

### Viewing logs
```bash
docker-compose logs -f
```

### Accessing check logs
```bash
docker-compose exec mailcheck cat /app/data/mailcheck.log
```

### Manually trigger checks
```bash
curl http://localhost:8080/api/worker
```

### Check system stats
```bash
curl http://localhost:8080/api/stats
```

## Common Issues Detected

### DNS Issues
- **No MX records** - Domain cannot receive email
- **Missing SPF** - Emails may be marked as spam
- **Missing DMARC** - No email authentication policy

### Connectivity Issues
- **All SMTP ports closed** - Mail server unreachable
- **Port 587 closed** - Modern submission port unavailable

### Certificate Issues
- **Certificate expiring soon** - 30-day warning
- **Certificate expired** - Immediate alert
- **Certificate unavailable** - STARTTLS failed

## Limitations

- One monitor per email address (by design)
- DKIM requires knowing the selector (not auto-detected)
- Email alerts require working SMTP configuration
- No authentication/authorization (suitable for internal use)
- Basic SQL injection protection (use prepared statements in production)

## Security Considerations

This tool is designed for personal/internal use. For public deployment, add:
- Email verification
- Rate limiting
- SQL injection protection (prepared statements)
- CAPTCHA
- Input sanitization
- Authentication system

## License

MIT License - Feel free to modify and use as needed.
