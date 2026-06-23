from __future__ import annotations

import asyncio
import logging
import os
import sqlite3
import sys
from contextlib import asynccontextmanager, suppress
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.config import get_settings

BASE_DIR = Path(__file__).resolve().parent.parent
BOT_DIR = BASE_DIR / "bot"
STATIC_DIR = BASE_DIR / "static"
MINIAPP_DIR = STATIC_DIR / "miniapp"

sys.path.insert(0, str(BOT_DIR))

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("cb_balloons_bot")


def _ensure_data_dir() -> None:
    settings = get_settings()
    db_path = Path(settings.db_file)
    db_path.parent.mkdir(parents=True, exist_ok=True)


def _admin_ok(token: str | None) -> bool:
    expected = get_settings().admin_token
    return bool(expected and token and token == expected)


def _stats() -> dict:
    settings = get_settings()
    db_path = Path(settings.db_file)
    if not db_path.exists():
        return {"players": 0, "games_played": 0, "top_score": 0}
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT COUNT(DISTINCT user_id), COALESCE(SUM(games_played), 0), COALESCE(MAX(max_points), 0) FROM scores")
    row = cur.fetchone() or (0, 0, 0)
    conn.close()
    return {"players": row[0], "games_played": row[1], "top_score": row[2]}


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    os.environ.setdefault("DB_FILE", settings.db_file)
    os.environ.setdefault("TELEGRAM_BOT_TOKEN", settings.telegram_bot_token)
    os.environ.setdefault("TELEGRAM_MINI_APP_URL", settings.telegram_mini_app_url)
    os.environ.setdefault("MAX_APP_URL", settings.max_app_url)
    os.environ.setdefault("BOSS_ID", str(settings.boss_id))
    _ensure_data_dir()
    task: asyncio.Task | None = None
    if settings.telegram_polling_enabled and settings.telegram_bot_token:
        from CB_Balloons import build_application, configure_commands

        application = build_application()
        await application.initialize()
        await configure_commands(application)
        await application.start()
        await application.updater.start_polling(drop_pending_updates=False)
        log.info("telegram polling started for cb-balloons")
        task = asyncio.create_task(_poll_guard(application))
    else:
        log.warning("telegram polling disabled or token missing")
    try:
        yield
    finally:
        if task:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
        if settings.telegram_polling_enabled and settings.telegram_bot_token:
            with suppress(Exception):
                await application.updater.stop()
                await application.stop()
                await application.shutdown()


async def _poll_guard(application) -> None:
    try:
        while True:
            await asyncio.sleep(3600)
    except asyncio.CancelledError:
        raise


app = FastAPI(title="CB Balloons Bot", version="1.0.0", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "same-origin"
    return response


@app.get("/health")
def health():
    settings = get_settings()
    return {
        "status": "healthy",
        "service": "cb-balloons-bot",
        "telegram_polling": settings.telegram_polling_enabled and bool(settings.telegram_bot_token),
        "mini_app_configured": bool(settings.telegram_mini_app_url),
        "max_app_configured": bool(settings.max_app_url),
    }


@app.get("/ready")
def ready():
    return {"ok": True, "stats": _stats()}


@app.get("/")
def root():
    return {
        "ok": True,
        "service": "cb-balloons-bot",
        "miniapp": "/miniapp",
        "health": "/health",
    }


@app.get("/miniapp")
def miniapp():
    return FileResponse(MINIAPP_DIR / "index.html")


@app.get("/api/stats")
def api_stats():
    return _stats()


@app.get("/admin/summary")
def admin_summary(x_admin_token: str | None = Header(default=None)):
    if not _admin_ok(x_admin_token):
        raise HTTPException(status_code=401, detail="unauthorized")
    settings = get_settings()
    return {
        "service": "cb-balloons-bot",
        "stats": _stats(),
        "mini_app_url": settings.telegram_mini_app_url,
        "max_app_url": settings.max_app_url,
    }


@app.post("/webhooks/max")
async def max_webhook(request: Request):
    settings = get_settings()
    if settings.max_webhook_secret:
        got = request.headers.get("x-max-bot-api-secret") or request.headers.get("x-webhook-token")
        if got != settings.max_webhook_secret:
            raise HTTPException(status_code=403, detail="bad max webhook token")
    payload = await request.json()
    return {"ok": True, "platform": "max", "accepted": bool(payload), "stage": "cb-balloons-max-bridge"}
