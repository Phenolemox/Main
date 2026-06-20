from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health():
    return {"status": "healthy", "service": "poker-bot", "version": "0.1.0"}


@router.get("/ready")
async def ready():
    return {"ok": True}
