import os
from functools import lru_cache


class Settings:
    host: str = os.getenv("CB_BALLOONS_HOST", "10.8.0.1")
    port: int = int(os.getenv("CB_BALLOONS_PORT", "8160"))
    public_base_url: str = os.getenv("PUBLIC_BASE_URL", "").rstrip("/")
    telegram_bot_token: str = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    telegram_polling_enabled: bool = os.getenv("TELEGRAM_POLLING_ENABLED", "true").lower() in {"1", "true", "yes"}
    telegram_mini_app_url: str = os.getenv("TELEGRAM_MINI_APP_URL", "").strip()
    max_app_url: str = os.getenv("MAX_APP_URL", "").strip()
    max_webhook_secret: str = os.getenv("MAX_WEBHOOK_SECRET", "").strip()
    admin_token: str = os.getenv("ADMIN_TOKEN", "").strip()
    boss_id: int = int(os.getenv("BOSS_ID", "484184861"))
    db_file: str = os.getenv("DB_FILE", "/opt/data/cb-balloons/balloon_game.db")


@lru_cache
def get_settings() -> Settings:
    return Settings()
