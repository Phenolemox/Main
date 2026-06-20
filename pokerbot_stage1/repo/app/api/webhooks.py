from fastapi import APIRouter, Request

router = APIRouter(prefix="/webhooks")


@router.post("/telegram")
async def telegram_webhook(request: Request):
    update = await request.json()
    return {"ok": True, "platform": "telegram", "accepted": bool(update)}


@router.post("/max")
async def max_webhook(request: Request):
    update = await request.json()
    return {"ok": True, "platform": "max", "accepted": bool(update)}
