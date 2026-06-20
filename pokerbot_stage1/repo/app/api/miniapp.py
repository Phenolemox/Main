from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.config import get_settings
from app.core.security import AuthError, validate_webapp_init_data
from app.game.achievements import ACHIEVEMENTS

router = APIRouter(prefix="/api/miniapp")


class LoginIn(BaseModel):
    platform: str
    init_data: str


@router.post("/login")
async def miniapp_login(payload: LoginIn):
    settings = get_settings()
    platform = payload.platform.lower()
    if platform == "telegram":
        token = settings.telegram_bot_token
    elif platform == "max":
        token = settings.max_bot_token
    else:
        token = None
    if not token:
        raise HTTPException(status_code=400, detail="platform token not configured")
    try:
        data = validate_webapp_init_data(payload.init_data, token)
    except AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    return {"ok": True, "platform": platform, "profile": data}


@router.get("/achievements")
async def achievements():
    return {"items": ACHIEVEMENTS}
