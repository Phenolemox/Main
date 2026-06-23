"""Подключение к БД, инициализация схемы и миграции.

ВАЖНО (исправление главного бага «зависания на раунде 5»):
Раньше init_db() создавал таблицу scores только с базовыми колонками, тогда как
update_scores() писал в колонки по цветам (blue_spheres, red_triplets, green_nions
и т.д.), которые в схеме отсутствовали. В конце 5-го раунда INSERT падал с
sqlite3.OperationalError, исключение всплывало до edit_message_text, и кнопка
«Принять» «висела» вечно.

Теперь схема создаётся со ВСЕМИ колонками, а для уже существующих баз выполняется
миграция: недостающие колонки добавляются через ALTER TABLE ADD COLUMN.
"""
from __future__ import annotations

import datetime
import sqlite3
from contextlib import contextmanager
from zoneinfo import ZoneInfo

from bot_config import DB_FILE, TIMEZONE

# Базовые колонки scores
BASE_COLUMNS = [
    ("user_id", "INTEGER"),
    ("username", "TEXT"),
    ("chat_id", "INTEGER"),
    ("points", "INTEGER DEFAULT 0"),
    ("last_play", "TEXT"),
    ("games_played", "INTEGER DEFAULT 0"),
    ("max_points", "INTEGER DEFAULT 0"),
    ("total_points", "INTEGER DEFAULT 0"),
    ("triplets", "INTEGER DEFAULT 0"),
    ("nions", "INTEGER DEFAULT 0"),
    ("achievement_points", "INTEGER DEFAULT 0"),
]

# Колонки по цветам — раньше их не было в схеме, из-за чего падал update_scores
COLOR_COLUMNS = [
    ("blue_spheres", "INTEGER DEFAULT 0"),
    ("red_spheres", "INTEGER DEFAULT 0"),
    ("green_spheres", "INTEGER DEFAULT 0"),
    ("gold_spheres", "INTEGER DEFAULT 0"),
    ("purple_spheres", "INTEGER DEFAULT 0"),
    ("blue_triplets", "INTEGER DEFAULT 0"),
    ("red_triplets", "INTEGER DEFAULT 0"),
    ("green_triplets", "INTEGER DEFAULT 0"),
    ("purple_triplets", "INTEGER DEFAULT 0"),
    ("green_nions", "INTEGER DEFAULT 0"),
]

ALL_COLUMNS = BASE_COLUMNS + COLOR_COLUMNS


def now_iso() -> str:
    return datetime.datetime.now(ZoneInfo(TIMEZONE)).isoformat()


def today():
    return datetime.datetime.now(ZoneInfo(TIMEZONE)).date()


@contextmanager
def connect():
    conn = sqlite3.connect(DB_FILE)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _column_defs() -> str:
    defs = ",\n        ".join(f"{name} {ctype}" for name, ctype in ALL_COLUMNS)
    return defs


def init_db() -> None:
    with connect() as conn:
        c = conn.cursor()
        c.execute(
            f"""
            CREATE TABLE IF NOT EXISTS scores (
                {_column_defs()},
                PRIMARY KEY (user_id, chat_id)
            )
            """
        )
        c.execute(
            """
            CREATE TABLE IF NOT EXISTS user_achievements (
                user_id INTEGER,
                chat_id INTEGER,
                achievement_id TEXT,
                PRIMARY KEY (user_id, chat_id, achievement_id)
            )
            """
        )
        # Миграция существующих баз: добавляем недостающие колонки.
        c.execute("PRAGMA table_info(scores)")
        existing = {row[1] for row in c.fetchall()}
        for name, ctype in ALL_COLUMNS:
            if name not in existing:
                c.execute(f"ALTER TABLE scores ADD COLUMN {name} {ctype}")


def save_user(user_id: int, username: str | None) -> None:
    with connect() as conn:
        conn.execute(
            "INSERT OR IGNORE INTO scores (user_id, username, chat_id) VALUES (?, ?, ?)",
            (user_id, username or "Unknown", 0),
        )
        conn.execute(
            "UPDATE scores SET username = ? WHERE user_id = ? AND chat_id = 0",
            (username or "Unknown", user_id),
        )


def touch_last_play(user_id: int, chat_id: int) -> None:
    now = now_iso()
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO scores (user_id, chat_id, last_play)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id, chat_id) DO UPDATE SET last_play = ?
            """,
            (user_id, chat_id, now, now),
        )


def already_played_today(user_id: int, chat_id: int) -> bool:
    with connect() as conn:
        row = conn.execute(
            "SELECT last_play FROM scores WHERE user_id = ? AND chat_id = ?",
            (user_id, chat_id),
        ).fetchone()
    if not row or not row[0]:
        return False
    try:
        return datetime.datetime.fromisoformat(row[0]).date() == today()
    except ValueError:
        return False
