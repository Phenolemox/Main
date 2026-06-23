"""Конфигурация окружения бота CB Balloons."""
from __future__ import annotations

import os

TOKEN: str = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
BOSS_ID: int = int(os.getenv("BOSS_ID", "484184861"))
DB_FILE: str = os.getenv("DB_FILE", "balloon_game.db")
MINI_APP_URL: str = os.getenv("TELEGRAM_MINI_APP_URL", "").strip()
MAX_APP_URL: str = os.getenv("MAX_APP_URL", "").strip()

TOTAL_ROUNDS: int = 5
TIMEZONE: str = "Europe/Moscow"

HOW_PHOTO_FILE_ID: str = (
    "AgACAgIAAxkBAAIDbmgrcf9D_621osyFbtvIURa5j8ESAALY7zEbOhJgSdxOt1Ty8xagAQADAgADeAADNgQ"
)
