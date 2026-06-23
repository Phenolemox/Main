from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

APP_NAME = "bots-hub"
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"

BOTS = [
    {
        "id": "poker-bot",
        "name": "MyPoker",
        "emoji": "🃏",
        "description": "Telegram poker с дуэлями, рейтингами и Mini App",
        "health_url": "http://10.8.0.1:8140/health",
        "miniapp_url": "http://10.8.0.1:8140/miniapp",
        "telegram": "https://t.me/mypokerbotofficial_bot",
    },
    {
        "id": "cb-balloons",
        "name": "CB Balloons",
        "emoji": "🎈",
        "description": "Игра со сферами, достижениями и таблицами лидеров",
        "health_url": "http://10.8.0.1:8160/health",
        "miniapp_url": "http://10.8.0.1:8160/miniapp",
        "telegram": "https://t.me/CB_Balloonsbot",
    },
    {
        "id": "autobot",
        "name": "Autobot",
        "emoji": "🚓",
        "description": "Генератор номерных знаков с очками и обменом",
        "health_url": "http://10.8.0.1:8161/health",
        "miniapp_url": "http://10.8.0.1:8161/miniapp",
        "telegram": "https://t.me/Inspectorauto_bot",
    },
]

app = FastAPI(title="Phenolemox Bots Hub", version="1.0.0")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/health")
def health():
    return {"status": "healthy", "service": APP_NAME}


@app.get("/api/bots")
def api_bots():
    return {"items": BOTS}


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")
