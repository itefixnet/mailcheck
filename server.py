#!/usr/bin/env python3
import asyncio
import json
import subprocess
import os
import time
from collections import defaultdict
from aiohttp import web
import aiohttp

MAX_CONCURRENT = int(os.getenv('MAX_PARALLEL_CHECKS', '10'))
semaphore = asyncio.Semaphore(MAX_CONCURRENT)

# Rate limiting: track IP requests
ip_requests = defaultdict(list)
RATE_LIMIT_WINDOW = 900  # 15 minutes in seconds
RATE_LIMIT_MAX = 3

def check_rate_limit(ip):
    """Check if IP has exceeded rate limit"""
    now = time.time()
    # Remove old requests outside the 15-minute window
    ip_requests[ip] = [t for t in ip_requests[ip] if now - t < RATE_LIMIT_WINDOW]
    
    if len(ip_requests[ip]) >= RATE_LIMIT_MAX:
        return False  # Rate limit exceeded
    
    # Add current request
    ip_requests[ip].append(now)
    return True

async def websocket_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    # Get client IP
    client_ip = request.headers.get('X-Forwarded-For', request.remote)
    if ',' in client_ip:
        client_ip = client_ip.split(',')[0].strip()
    
    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            try:
                data = json.loads(msg.data)
                domain = data.get('domain', '').strip()
                
                if not domain:
                    await ws.send_json({'error': 'Domain is required'})
                    continue
                
                # Check rate limit
                if not check_rate_limit(client_ip):
                    await ws.send_json({'error': 'Rate limit exceeded. Maximum 3 checks per 15 minutes. Please try again later.'})
                    continue
                
                async with semaphore:
                    await run_checks(ws, domain)
                    
            except json.JSONDecodeError:
                await ws.send_json({'error': 'Invalid JSON'})
            except Exception as e:
                await ws.send_json({'error': str(e)})
    
    return ws

async def run_checks(ws, domain):
    """Run mail server checks with progress updates"""
    
    await ws.send_json({'type': 'progress', 'step': 'starting', 'message': 'Starting mail server health check...'})
    
    # Run the bash script
    proc = await asyncio.create_subprocess_exec(
        '/app/scripts/check.sh',
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env={'v_v_domain': domain, **os.environ}
    )
    
    # Wait with a timeout and send periodic updates
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30.0)
    except asyncio.TimeoutError:
        proc.kill()
        await ws.send_json({'error': 'Check timed out after 30 seconds'})
        return
    
    if proc.returncode == 0:
        try:
            result = json.loads(stdout.decode())
            await ws.send_json({'type': 'complete', 'data': result})
        except json.JSONDecodeError:
            await ws.send_json({'error': 'Invalid response from checker', 'output': stdout.decode()})
    else:
        await ws.send_json({'error': 'Check failed', 'stderr': stderr.decode()})

async def index_handler(request):
    with open('/app/frontend/index.html', 'r') as f:
        return web.Response(text=f.read(), content_type='text/html')

async def health_handler(request):
    return web.json_response({'status': 'ok'})

app = web.Application()
app.router.add_get('/', index_handler)
app.router.add_get('/ws', websocket_handler)
app.router.add_get('/health', health_handler)

if __name__ == '__main__':
    web.run_app(app, host='0.0.0.0', port=8080)
