from fastapi import APIRouter, Header, HTTPException

from app.core.config import get_settings
from app.core.security import validate_webhook_secret

router = APIRouter(prefix="/admin")


def _guard(token: str | None):
    settings = get_settings()
    if settings.admin_token and not validate_webhook_secret(token, settings.admin_token):
        raise HTTPException(status_code=401, detail="bad admin token")


@router.get("/health")
async def admin_health(x_admin_token: str | None = Header(default=None)):
    _guard(x_admin_token)
    return {"ok": True, "admin": True}
