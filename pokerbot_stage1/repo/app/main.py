from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.api.admin import router as admin_router
from app.api.health import router as health_router
from app.api.miniapp import router as miniapp_router
from app.api.webhooks import router as webhooks_router

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"

app = FastAPI(title="Poker Bot API", version="0.1.0")

app.include_router(health_router)
app.include_router(webhooks_router)
app.include_router(miniapp_router)
app.include_router(admin_router)

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
async def root():
    return {"ok": True, "service": "poker-bot"}


@app.get("/miniapp")
async def miniapp():
    return FileResponse(STATIC_DIR / "miniapp" / "index.html")
