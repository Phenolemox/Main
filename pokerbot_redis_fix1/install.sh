#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

cat > app/core/redis_client.py <<'PY'
from __future__ import annotations
import time
from typing import Any
import redis.asyncio as redis
from app.core.config import get_settings

_client: redis.Redis | None = None


def get_redis_url() -> str | None:
    return get_settings().redis_url


async def get_redis() -> redis.Redis | None:
    global _client
    url = get_redis_url()
    if not url:
        return None
    if _client is None:
        _client = redis.from_url(url, decode_responses=True)
    return _client


async def redis_health() -> dict[str, Any]:
    client = await get_redis()
    if client is None:
        return {"ok": False, "configured": False, "error": "not_configured"}
    started = time.perf_counter()
    try:
        pong = await client.ping()
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        info = await client.info(section="memory")
        return {"ok": bool(pong), "configured": True, "latency_ms": elapsed_ms, "used_memory_human": info.get("used_memory_human")}
    except Exception as e:
        return {"ok": False, "configured": True, "error": type(e).__name__}
PY

./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q
git add .
git commit -m 'Fix Redis health error handling' || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

cd /opt/apps/poker-bot
./.venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
import asyncio, re
import redis.asyncio as redis

ENV = Path('/opt/apps/poker-bot/.env')

def read_env(path):
    data = {}
    if not path.exists(): return data
    for line in path.read_text(errors='ignore').splitlines():
        if '=' in line and not line.strip().startswith('#'):
            k,v=line.split('=',1); data[k.strip()] = v.strip().strip('"\'')
    return data

def write_env(data):
    order=['APP_ENV','PUBLIC_BASE_URL','INTERNAL_BASE_URL','DATABASE_URL','REDIS_URL','TELEGRAM_BOT_TOKEN','TELEGRAM_WEBHOOK_SECRET','TELEGRAM_POLLING_ENABLED','MAX_BOT_TOKEN','MAX_WEBHOOK_SECRET','ADMIN_TOKEN','BOSS_PLATFORM','BOSS_PLATFORM_USER_ID']
    keys = order + sorted(k for k in data if k not in order)
    ENV.write_text('\n'.join(f'{k}={data.get(k,"")}' for k in keys) + '\n')

async def ok(url):
    try:
        c = redis.from_url(url, decode_responses=True)
        await c.ping(); await c.aclose(); return True
    except Exception:
        return False

async def main():
    data = read_env(ENV)
    base = data.get('REDIS_URL','redis://10.8.0.1:6379/2') or 'redis://10.8.0.1:6379/2'
    candidates = []
    if '@' in base: candidates.append(base)
    passwords = []
    for path in list(Path('/opt/apps').glob('*/.env')) + [Path('/opt/data/ai-control-room/state/current.env'), Path('/etc/redis/redis.conf')]:
        if not path.exists(): continue
        txt = path.read_text(errors='ignore')
        for line in txt.splitlines():
            low=line.lower().strip()
            if low.startswith('redis_url=') and '@' in line:
                candidates.append(line.split('=',1)[1].strip().strip('"\''))
            if low.startswith(('redis_password=','redis_pass=','requirepass ')):
                passwords.append(line.split(None,1)[1].strip() if ' ' in line and '=' not in line else line.split('=',1)[1].strip())
    for pwd in passwords:
        pwd = pwd.strip().strip('"\'')
        if pwd and pwd not in ('', 'changeme'):
            candidates.append('redis://:' + quote(pwd, safe='') + '@10.8.0.1:6379/2')
    for url in candidates:
        if await ok(url):
            data['REDIS_URL'] = url
            write_env(data)
            print('REDIS_AUTH_OK')
            return
    print('REDIS_AUTH_NOT_FOUND')
asyncio.run(main())
PY
chmod 600 .env

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health
curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/redis && echo
echo REDIS_FIX1_DONE
