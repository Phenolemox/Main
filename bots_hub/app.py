import json
import os
import time
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

APP_NAME = "bots-hub"
APP_VERSION = "1.1.0"
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
PUBLIC_DOMAIN = os.getenv("PUBLIC_DOMAIN", "ai-alliance.pro").strip()

# Internal health URLs (10.8.0.1) are reachable from this service but NOT from a
# public browser. The hub queries them server-side and only exposes public HTTPS
# links to the client, which fixes the "0 online / N offline" issue.
BOTS = [
    {
        "id": "poker-bot",
        "name": "MyPoker",
        "emoji": "🃏",
        "description": "Telegram и MAX покер с дуэлями, рейтингами и Mini App",
        "internal_health": "http://10.8.0.1:8140/health",
        "public": f"https://poker.{PUBLIC_DOMAIN}",
        "miniapp_url": f"https://poker.{PUBLIC_DOMAIN}/miniapp",
        "max_webhook": f"https://poker.{PUBLIC_DOMAIN}/webhooks/max",
        "telegram": "https://t.me/mypokerbotofficial_bot",
    },
    {
        "id": "cb-balloons",
        "name": "CB Balloons",
        "emoji": "🎈",
        "description": "Игра со сферами, достижениями и таблицами лидеров",
        "internal_health": "http://10.8.0.1:8160/health",
        "public": f"https://balloons.{PUBLIC_DOMAIN}",
        "miniapp_url": f"https://balloons.{PUBLIC_DOMAIN}/miniapp",
        "max_webhook": f"https://balloons.{PUBLIC_DOMAIN}/webhooks/max",
        "telegram": "https://t.me/CB_Balloonsbot",
    },
    {
        "id": "autobot",
        "name": "Autobot",
        "emoji": "🚓",
        "description": "Генератор номерных знаков с очками и обменом",
        "internal_health": "http://10.8.0.1:8161/health",
        "public": f"https://autobot.{PUBLIC_DOMAIN}",
        "miniapp_url": f"https://autobot.{PUBLIC_DOMAIN}/miniapp",
        "max_webhook": f"https://autobot.{PUBLIC_DOMAIN}/webhooks/max",
        "telegram": "https://t.me/Inspectorauto_bot",
    },
]

app = FastAPI(title="Phenolemox Bots Hub", version=APP_VERSION)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


def check_health(url: str, timeout: int = 4) -> dict[str, Any]:
    started = time.time()
    try:
        with urlopen(url, timeout=timeout) as response:
            body = response.read(50_000).decode("utf-8", "replace")
            status = response.status
    except URLError as exc:
        return {"online": False, "status": "offline", "error": str(exc.reason)}
    except Exception as exc:  # noqa: BLE001
        return {"online": False, "status": "offline", "error": str(exc)}
    try:
        parsed = json.loads(body)
    except Exception:  # noqa: BLE001
        parsed = {}
    online = 200 <= status < 300 and parsed.get("status") == "healthy"
    return {
        "online": online,
        "status": "online" if online else "degraded",
        "http_status": status,
        "latency_ms": round((time.time() - started) * 1000),
        "detail": parsed,
    }


@app.get("/health")
def health():
    return {"status": "healthy", "service": APP_NAME, "version": APP_VERSION}


@app.get("/api/bots")
def api_bots():
    items = []
    online = 0
    for bot in BOTS:
        health = check_health(bot["internal_health"])
        if health["online"]:
            online += 1
        public = {k: v for k, v in bot.items() if k != "internal_health"}
        public["health"] = health
        items.append(public)
    return {
        "items": items,
        "total": len(items),
        "online": online,
        "offline": len(items) - online,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")
