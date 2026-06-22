from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .routes_admin import router as admin_router
from .routes_player import router as player_router
from .storage import init_db

ROOT = Path(__file__).resolve().parent.parent
STATIC = ROOT / "static"

app = FastAPI(title="PCF Fight Manager Engine", version="0.1.0")


@app.on_event("startup")
def startup() -> None:
    init_db()


app.include_router(player_router)
app.include_router(admin_router)
app.mount("/static", StaticFiles(directory=STATIC), name="static")


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC / "index.html")


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}
