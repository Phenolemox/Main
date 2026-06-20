from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "dev"
    public_base_url: str = "http://10.8.0.1:8140"
    internal_base_url: str = "http://10.8.0.1:8140"

    database_url: str = "sqlite+aiosqlite:///./pokerbot_dev.db"
    redis_url: str | None = None

    telegram_bot_token: str | None = None
    telegram_webhook_secret: str | None = None

    max_bot_token: str | None = None
    max_webhook_secret: str | None = None

    admin_token: str | None = None
    boss_platform: str | None = None
    boss_platform_user_id: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
