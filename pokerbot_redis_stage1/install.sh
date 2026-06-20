#!/usr/bin/env bash
set -euo pipefail

cd /opt/repos/poker-bot
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

mkdir -p app/core app/api tests

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
        return {"ok": False, "configured": False}
    started = time.perf_counter()
    pong = await client.ping()
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    info = await client.info(section="memory")
    return {
        "ok": bool(pong),
        "configured": True,
        "latency_ms": elapsed_ms,
        "used_memory_human": info.get("used_memory_human"),
    }


async def redis_set_json(key: str, value: str, ttl_seconds: int) -> None:
    client = await get_redis()
    if client is None:
        raise RuntimeError("Redis is not configured")
    await client.set(key, value, ex=ttl_seconds)


async def redis_get(key: str) -> str | None:
    client = await get_redis()
    if client is None:
        raise RuntimeError("Redis is not configured")
    return await client.get(key)


async def redis_delete(key: str) -> None:
    client = await get_redis()
    if client is None:
        raise RuntimeError("Redis is not configured")
    await client.delete(key)
PY

cat > app/api/ops.py <<'PY'
from fastapi import APIRouter

from app.core.redis_client import redis_health

router = APIRouter(prefix="/ops")


@router.get("/redis")
async def ops_redis():
    return await redis_health()
PY

python3 - <<'PY'
from pathlib import Path
p = Path('app/main.py')
s = p.read_text(encoding='utf-8')
if 'from app.api.ops import router as ops_router' not in s:
    marker = 'from app.api.miniapp import router as miniapp_router\n'
    s = s.replace(marker, marker + 'from app.api.ops import router as ops_router\n')
if 'app.include_router(ops_router)' not in s:
    marker = 'app.include_router(miniapp_router)\n'
    s = s.replace(marker, marker + 'app.include_router(ops_router)\n')
p.write_text(s, encoding='utf-8')
PY

cat > tests/test_redis_client.py <<'PY'
from app.core.redis_client import get_redis_url


def test_redis_url_function_exists():
    assert get_redis_url is not None
PY

./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git add .
git commit -m 'Add Redis ops layer stage 1' || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/redis && echo

echo REDIS_STAGE1_DONE
