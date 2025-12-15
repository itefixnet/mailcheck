# MailCheck - Mail Server Health Monitoring

A minimal, stateless mail server health monitoring service using pure shell scripts with socat as the web server.

## Features

- 📧 **MX Records Check** - Verifies mail server configuration
- 🔒 **SSL/TLS Certificate Monitoring** - Checks SMTP certificate validity and expiration
- 🌐 **DNS Records** - Validates SPF and DMARC records
- 🔌 **Port Connectivity** - Tests SMTP (25, 587, 465), IMAP (993), POP3 (995)
- 🚫 **RBL Blacklist Checks** - Tests against major spam blacklists (Spamhaus, SpamCop, etc.)
- 🔓 **Open Relay Detection** - Security check for misconfigured mail servers
- 📊 **Simple HTTP Interface** - Clean POST-based API
- ⚡ **Concurrent Checks** - Lock-file based parallel processing
- ⏱️ **Performance Metrics** - Response time tracking for all checks
- 🐳 **Fully Dockerized** - Pure shell, no Python/Node.js required
- 🪶 **Lightweight** - Alpine-based, <50MB image

## Quick Start

### Prerequisites

- Docker (Docker Compose optional)

### Setup

1. Clone this repository:
```bash
git clone <your-repo>
cd mailcheck
```

2. Build and run with Docker:
```bash
docker build -t mailcheck:latest .
docker run -d \
  --name mailcheck \
  --restart unless-stopped \
  -p 8080:8080 \
  -e MAX_PARALLEL_CHECKS=10 \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  mailcheck:latest
```

4. Access the web interface:
```
http://localhost:8080
```

## What It Checks

### DNS Records
- **MX Records** - Mail server addresses and IP resolution
- **SPF Record** - Sender Policy Framework for anti-spoofing
- **DMARC Record** - Domain-based Message Authentication
- **DKIM Records** - Checks common selectors (default, selector1, selector2, google, k1, dkim, s1, s2, mail, email)

### Port Connectivity
- **Port 25** - Standard SMTP
- **Port 587** - SMTP Submission (recommended)
- **Port 465** - SMTP over SSL (legacy)
- **Port 993** - IMAP over SSL
- **Port 995** - POP3 over SSL

### SSL/TLS Certificates
- Certificate validity (tries ports 587, 465, 25 with STARTTLS)
- Expiration date and days remaining
- Status: ok (>30 days), warning (<30 days), error (expired)

### Security & Reputation
- **RBL Blacklist Check** - Tests against Spamhaus, SpamCop, Barracuda, CBL, UCEPROTECT
- **Open Relay Test** - Detects misconfigured mail servers that allow relaying

### Performance
- **Response Times** - Individual timing for each check component (DNS, ports, SSL, RBL, relay)

## Configuration

### Concurrent Checks

By default, the system allows up to 10 concurrent checks. Configure via environment variable:

```bash
docker run -d \
  -p 8080:8080 \
  -e MAX_PARALLEL_CHECKS=20 \
  mailcheck:latest
```

### RBL Servers

Customize blacklist servers to check:

```bash
docker run -d \
  -p 8080:8080 \
  -e RBL_SERVERS="zen.spamhaus.org:Spamhaus,bl.spamcop.net:SpamCop" \
  mailcheck:latest
```

## Usage

### Check a Mail Server

1. Visit http://localhost:8080
2. Enter the mail server domain (e.g., `gmail.com` or `yourdomain.com`)
3. Click "Check Server"
4. View results:
   - MX records and IP address
   - SPF, DMARC, and DKIM records
   - Port connectivity (SMTP, IMAP, POP3)
   - SSL certificate validity and expiration
   - RBL blacklist status
   - Open relay security check
   - Performance timing for each component

## API Endpoints

### GET /
Serves the web interface.

### POST /check
Runs mail server health check.

**Request:**
```
POST /check
Content-Type: application/x-www-form-urlencoded

domain=example.com
```

**Response:**
```json
{
  "domain": "example.com",
    "status": "ok",
    "checked_at": "2025-12-15 12:34:56",
    "mx_records": "10 mail.example.com.",
    "mx_status": "ok",
    "mx_ip": "192.0.2.1",
    "spf_record": "v=spf1 include:_spf.example.com ~all",
    "spf_status": "ok",
    "dmarc_record": "v=DMARC1; p=quarantine",
    "dmarc_status": "ok",
    "dkim_status": "ok",
    "dkim_message": "found (default google)",
    "dkim_records": [
      "default: v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC...",
      "google: v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA..."
    ],
    "rbl_status": "ok",
    "rbl_message": "not listed on any blacklists",
    "rbl_results": [
      {"name": "Spamhaus", "status": "clean"},
      {"name": "SpamCop", "status": "clean"}
    ],
    "smtp_port_25": "open",
    "smtp_port_587": "open",
    "smtp_port_465": "closed",
    "imap_port_993": "open",
    "pop3_port_995": "closed",
    "smtp_ssl_valid": "valid",
    "smtp_ssl_expiry": "Jan 1 00:00:00 2026 GMT",
    "smtp_ssl_days_remaining": 382,
    "smtp_ssl_status": "ok",
    "open_relay_status": "ok",
    "open_relay_message": "relay properly restricted",
    "response_times": {
      "dns_ms": 123,
      "spf_ms": 45,
      "dmarc_ms": 67,
      "dkim_ms": 89,
      "rbl_ms": 234,
      "ports_ms": 345,
      "ssl_ms": 456,
      "relay_ms": 567,
      "total_ms": 1926
    }
}
```

**Error Response:**
```json
{
  "error": "Domain is required"
}
```

### GET /health
Health check endpoint.

**Response:**
```json
{
  "status": "ok"
}
```

## Architecture

- **Pure Shell** - No Python, Node.js, or other runtimes required
- **Socat HTTP Server** - Lightweight TCP server with bash request handling
- **Stateless** - No database, no persistent storage
- **On-demand** - Checks run only when requested by users
- **Concurrent** - Lock-file based parallel processing (default 10)
- **Timeout-protected** - Individual timeouts for each check component

Each check performs:
1. DNS lookups (MX, SPF, DMARC) with 5-second timeouts
2. DKIM record detection (tries 10 common selectors)
3. RBL blacklist queries against 5 major lists
4. Port connectivity tests (SMTP 25/587/465, IMAP 993, POP3 995)
5. SSL certificate validation with STARTTLS
6. Open relay security test (port 25)
7. Performance timing for all operations

## Project Structure

```
mailcheck/
├── Dockerfile              # Container definition (Alpine-based)
├── scripts/
│   ├── server.sh          # Socat-based HTTP server (pure bash)
│   └── check.sh           # Mail server health check script
└── frontend/
    └── index.html         # Web interface
```

## Development

### Building locally
```bash
docker build -t mailcheck .
```

### Stopping the service
```bash
docker stop mailcheck
docker rm mailcheck
```

### Viewing logs
```bash
docker logs -f mailcheck
```

### Testing the API
Using curl:
```bash
curl -X POST http://localhost:8080/check -d "domain=gmail.com"
```

### Health check
```bash
curl http://localhost:8080/health
```

## Common Issues Detected

### DNS Issues
- **No MX records** - Domain cannot receive email (status: error)
- **Missing SPF** - Emails may be marked as spam (status: warning)
- **Missing DMARC** - No email authentication policy (status: warning)
- **Missing DKIM** - Cannot verify email signatures (status: warning, checks common selectors)

### Reputation Issues
- **RBL listed** - Mail server on spam blacklist (status: error)
- **Open relay detected** - Security vulnerability (status: error)

### Connectivity Issues
- **All SMTP ports closed** - Mail server unreachable
- **Port 25 blocked** - Cannot test open relay

### Certificate Issues
- **Certificate expiring <30 days** - Warning status
- **Certificate expired** - Error status
- **Certificate unavailable** - STARTTLS failed (status: warning)

## Limitations

- **Stateless** - No persistent monitoring or historical data
- **No authentication** - Publicly accessible (use firewall/proxy for production)
- **No rate limiting** - Consider adding nginx/Cloudflare in front for production
- **DKIM selector detection** - Only tries common selectors (default, selector1, selector2, google, k1, dkim, s1, s2, mail, email)
- **Basic validation** - Domain format only, no advanced sanitization
- **Port 25 often blocked** - Open relay test may fail on many networks
- **RBL queries** - Dependent on external DNS services
- **Blocking requests** - Each request blocks during check (30s max)

## Security Considerations

This tool includes basic protections:
- ✅ Domain format validation
- ✅ Concurrent check limits (lock files)
- ✅ Timeout protection per check component
- ✅ Basic input sanitization

For public deployment, **MUST ADD**:
- Rate limiting (nginx, Cloudflare, fail2ban)
- CAPTCHA or proof-of-work
- Authentication/API keys
- DDoS protection
- Input sanitization for special characters
- Monitoring and alerting for abuse

**Note:** This is designed for personal/internal use. The socat server has no built-in rate limiting or request filtering.

## License

MIT License - Feel free to modify and use as needed.
