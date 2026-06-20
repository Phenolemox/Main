#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="Phenolemox/poker-bot"
TARGET_DIR="/opt/repos/poker-bot"

if [ ! -d "$TARGET_DIR/.git" ]; then
  rm -rf "$TARGET_DIR"
  gh repo clone "$TARGET_REPO" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
git remote set-url origin "https://github.com/${TARGET_REPO}.git" 2>/dev/null || true
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

python3 - <<'PY'
from pathlib import Path

root = Path('/opt/repos/poker-bot')
files = {
'app/core/config.py': r'''
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    app_env: str = 'dev'
    public_base_url: str = ''
    internal_base_url: str = 'http://10.8.0.1:8140'

    database_url: str = 'sqlite+aiosqlite:///./pokerbot_stage.db'
    redis_url: str | None = None

    telegram_bot_token: str | None = None
    telegram_webhook_secret: str | None = None
    telegram_polling_enabled: bool = False
    telegram_polling_interval: float = 1.0

    max_bot_token: str | None = None
    max_webhook_secret: str | None = None

    admin_token: str | None = None
    boss_platform: str | None = None
    boss_platform_user_id: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
'''.strip() + '\n',

'app/bot/telegram_poller.py': r'''
from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from app.bot.telegram import handle_telegram_update
from app.core.config import get_settings
from app.db.base import SessionLocal

log = logging.getLogger('poker_bot.telegram_poller')


async def _telegram_api(client: httpx.AsyncClient, token: str, method: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    url = f'https://api.telegram.org/bot{token}/{method}'
    response = await client.post(url, json=payload or {})
    try:
        body = response.json()
    except Exception:
        body = {'ok': False, 'raw': response.text[:500]}
    if not response.is_success:
        log.warning('telegram api %s http=%s body=%s', method, response.status_code, str(body)[:500])
    return body


async def telegram_polling_loop() -> None:
    settings = get_settings()
    token = settings.telegram_bot_token or ''
    if not token:
        log.warning('telegram polling requested but TELEGRAM_BOT_TOKEN is empty')
        return

    offset = 0
    backoff = 1.0

    async with httpx.AsyncClient(timeout=35) as client:
        try:
            await _telegram_api(client, token, 'deleteWebhook', {'drop_pending_updates': False})
            bootstrap = await _telegram_api(client, token, 'getUpdates', {'timeout': 0, 'limit': 100})
            updates = bootstrap.get('result') or []
            if updates:
                offset = max(int(u.get('update_id', 0)) for u in updates) + 1
                log.info('telegram polling skipped old updates count=%s offset=%s', len(updates), offset)
        except Exception:
            log.exception('telegram polling bootstrap failed')

        log.info('telegram polling started')
        while True:
            try:
                body = await _telegram_api(
                    client,
                    token,
                    'getUpdates',
                    {
                        'offset': offset,
                        'timeout': 25,
                        'limit': 50,
                        'allowed_updates': ['message', 'edited_message', 'callback_query'],
                    },
                )

                if not body.get('ok'):
                    await asyncio.sleep(backoff)
                    backoff = min(backoff * 2, 30)
                    continue

                backoff = 1.0
                for update in body.get('result') or []:
                    offset = int(update.get('update_id', offset)) + 1
                    try:
                        async with SessionLocal() as db:
                            await handle_telegram_update(update, db)
                    except Exception:
                        log.exception('telegram update handling failed')

            except asyncio.CancelledError:
                log.info('telegram polling stopped')
                raise
            except Exception:
                log.exception('telegram polling loop failed')
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 30)
'''.strip() + '\n',

'app/main.py': r'''
from contextlib import asynccontextmanager, suppress
from pathlib import Path
import asyncio
import logging

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.api.admin import router as admin_router
from app.api.game import router as game_router
from app.api.health import router as health_router
from app.api.leaderboards import router as leaderboards_router
from app.api.miniapp import router as miniapp_router
from app.api.webhooks import router as webhooks_router
from app.bot.telegram_poller import telegram_polling_loop
from app.core.config import get_settings
from app.db.base import SessionLocal, init_db
from app.db.repositories import seed_defaults

logging.basicConfig(level=logging.INFO)
log = logging.getLogger('poker_bot')

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / 'static'


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    async with SessionLocal() as db:
        await seed_defaults(db)

    task: asyncio.Task | None = None
    settings = get_settings()
    if settings.telegram_polling_enabled:
        task = asyncio.create_task(telegram_polling_loop())
        log.info('telegram polling task enabled')
    else:
        log.info('telegram polling task disabled')

    try:
        yield
    finally:
        if task:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


app = FastAPI(title='Poker Bot API', version='0.3.0', lifespan=lifespan)

app.include_router(health_router)
app.include_router(webhooks_router)
app.include_router(game_router)
app.include_router(leaderboards_router)
app.include_router(miniapp_router)
app.include_router(admin_router)

app.mount('/static', StaticFiles(directory=STATIC_DIR), name='static')


@app.get('/')
async def root():
    return {'ok': True, 'service': 'poker-bot', 'version': '0.3.0'}


@app.get('/miniapp')
async def miniapp():
    return FileResponse(STATIC_DIR / 'miniapp' / 'index.html')
'''.strip() + '\n',

'app/api/health.py': r'''
from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.base import get_db

router = APIRouter()


@router.get('/health')
async def health():
    settings = get_settings()
    return {
        'status': 'healthy',
        'service': 'poker-bot',
        'version': '0.3.0',
        'telegram_polling': bool(settings.telegram_polling_enabled),
    }


@router.get('/ready')
async def ready(db: AsyncSession = Depends(get_db)):
    await db.execute(text('SELECT 1'))
    return {'ok': True, 'db': 'ready'}
'''.strip() + '\n',

'tests/test_config_stage4.py': r'''
from app.core.config import Settings


def test_polling_flag_default_false():
    s = Settings()
    assert s.telegram_polling_enabled is False
'''.strip() + '\n',
}

for path, content in files.items():
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')

print(f'WROTE {len(files)} files into {root}')
PY

python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"

git add .
git commit -m "Add Telegram polling runtime stage 4" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo

echo "===== POKER BOT STAGE 4 DONE ====="
