from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

ROOT_DIR = Path(__file__).resolve().parent.parent
DB_PATH = Path(os.getenv("PCF_DB_PATH", str(ROOT_DIR / "pcf_engine.sqlite3")))


def utc_now() -> str:
    return datetime.utcnow().replace(microsecond=0).isoformat()


def connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {key: row[key] for key in row.keys()}


def rows_to_dicts(rows: Iterable[sqlite3.Row]) -> list[dict[str, Any]]:
    return [row_to_dict(row) for row in rows]  # type: ignore[list-item]


def scalar(conn: sqlite3.Connection, sql: str, args: tuple[Any, ...] = ()) -> Any:
    row = conn.execute(sql, args).fetchone()
    if row is None:
        return None
    return row[0]


def get_one(conn: sqlite3.Connection, sql: str, args: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    return row_to_dict(conn.execute(sql, args).fetchone())


def get_all(conn: sqlite3.Connection, sql: str, args: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    return rows_to_dicts(conn.execute(sql, args).fetchall())


def init_db() -> None:
    with connect() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'player',
                balance INTEGER NOT NULL DEFAULT 0,
                first_bet_done INTEGER NOT NULL DEFAULT 0,
                first_fighter_claimed INTEGER NOT NULL DEFAULT 0,
                manager_level INTEGER NOT NULL DEFAULT 1,
                telegram_id TEXT,
                max_id TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS fighters (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                nickname TEXT NOT NULL DEFAULT '',
                owner_user_id INTEGER,
                owner_status TEXT NOT NULL DEFAULT 'PCF',
                race TEXT NOT NULL DEFAULT '',
                creature_type TEXT NOT NULL DEFAULT '',
                planet TEXT NOT NULL DEFAULT '',
                country TEXT NOT NULL DEFAULT '',
                city TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                alt_description TEXT NOT NULL DEFAULT '',
                avatar_url TEXT NOT NULL DEFAULT '',
                poster_url TEXT NOT NULL DEFAULT '',
                rarity TEXT NOT NULL DEFAULT 'Common',
                title_status TEXT NOT NULL DEFAULT '',
                contract TEXT NOT NULL DEFAULT 'standard',
                status TEXT NOT NULL DEFAULT 'free',
                price INTEGER NOT NULL DEFAULT 0,
                for_sale INTEGER NOT NULL DEFAULT 0,
                physical_power INTEGER NOT NULL DEFAULT 1,
                magic INTEGER NOT NULL DEFAULT 1,
                speed INTEGER NOT NULL DEFAULT 1,
                intelligence INTEGER NOT NULL DEFAULT 1,
                media INTEGER NOT NULL DEFAULT 0,
                pcf_wins INTEGER NOT NULL DEFAULT 0,
                pcf_losses INTEGER NOT NULL DEFAULT 0,
                partner_record_json TEXT NOT NULL DEFAULT '{}',
                prompt TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                announcement_date TEXT,
                press_date TEXT,
                end_date TEXT,
                status TEXT NOT NULL DEFAULT 'draft',
                random_factor REAL NOT NULL DEFAULT 0.45,
                skill_factor REAL NOT NULL DEFAULT 0.55,
                event_type TEXT NOT NULL DEFAULT 'normal',
                is_canon INTEGER NOT NULL DEFAULT 1,
                published_on_home INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS event_fights (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER NOT NULL,
                fighter_a_id INTEGER NOT NULL,
                fighter_b_id INTEGER NOT NULL,
                odds_a REAL NOT NULL DEFAULT 1.8,
                odds_b REAL NOT NULL DEFAULT 1.8,
                fight_type TEXT NOT NULL DEFAULT 'normal',
                result TEXT NOT NULL DEFAULT '',
                winner_fighter_id INTEGER,
                method TEXT NOT NULL DEFAULT '',
                round INTEGER,
                admin_comment TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'open',
                created_at TEXT NOT NULL,
                FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE,
                FOREIGN KEY(fighter_a_id) REFERENCES fighters(id) ON DELETE CASCADE,
                FOREIGN KEY(fighter_b_id) REFERENCES fighters(id) ON DELETE CASCADE,
                FOREIGN KEY(winner_fighter_id) REFERENCES fighters(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS bets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                event_id INTEGER NOT NULL,
                fight_id INTEGER NOT NULL,
                chosen_fighter_id INTEGER NOT NULL,
                amount INTEGER NOT NULL,
                odds REAL NOT NULL,
                potential_payout INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE,
                FOREIGN KEY(fight_id) REFERENCES event_fights(id) ON DELETE CASCADE,
                FOREIGN KEY(chosen_fighter_id) REFERENCES fighters(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS training_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                fighter_id INTEGER NOT NULL,
                stat TEXT NOT NULL,
                started_at TEXT NOT NULL,
                finish_at TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                result_json TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY(fighter_id) REFERENCES fighters(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS fighter_proposals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                nickname TEXT NOT NULL DEFAULT '',
                race TEXT NOT NULL DEFAULT '',
                creature_type TEXT NOT NULL DEFAULT '',
                planet TEXT NOT NULL DEFAULT '',
                country TEXT NOT NULL DEFAULT '',
                city TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                alt_description TEXT NOT NULL DEFAULT '',
                avatar_url TEXT NOT NULL DEFAULT '',
                poster_url TEXT NOT NULL DEFAULT '',
                desired_contract TEXT NOT NULL DEFAULT 'standard',
                physical_power INTEGER NOT NULL DEFAULT 1,
                magic INTEGER NOT NULL DEFAULT 1,
                speed INTEGER NOT NULL DEFAULT 1,
                intelligence INTEGER NOT NULL DEFAULT 1,
                media INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'pending',
                admin_comment TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS announcements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                author_user_id INTEGER,
                scope TEXT NOT NULL DEFAULT 'pcf',
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(author_user_id) REFERENCES users(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS mechanic_modules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                color TEXT NOT NULL DEFAULT '#8f5cff',
                description TEXT NOT NULL DEFAULT '',
                active INTEGER NOT NULL DEFAULT 1,
                affects_fight INTEGER NOT NULL DEFAULT 1,
                poker_enabled INTEGER NOT NULL DEFAULT 1,
                visible_to_players INTEGER NOT NULL DEFAULT 1
            );
            """
        )
        seed_defaults(conn)
        conn.commit()


def seed_defaults(conn: sqlite3.Connection) -> None:
    now = utc_now()
    start_balance = int(os.getenv("PCF_START_BALANCE", "1500"))

    if scalar(conn, "SELECT COUNT(*) FROM users") == 0:
        conn.executemany(
            """
            INSERT INTO users
            (username, password, role, balance, first_bet_done, first_fighter_claimed, manager_level, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                ("admin", "admin", "admin", 50000, 0, 0, 99, now),
                ("player", "player", "player", start_balance, 0, 0, 1, now),
            ],
        )

    if scalar(conn, "SELECT COUNT(*) FROM settings") == 0:
        settings = {
            "bets_enabled": "1",
            "market_enabled": "1",
            "fighter_creation_enabled": "1",
            "training_enabled": "1",
            "poker_training_enabled": "1",
            "deadly_fights_enabled": "1",
            "partner_leagues_enabled": "0",
            "media_days_enabled": "1",
            "manual_result_enabled": "1",
            "random_result_enabled": "1",
            "training_seconds": os.getenv("PCF_TRAINING_SECONDS", "30"),
            "first_bet_bonus": "300",
        }
        conn.executemany("INSERT INTO settings(key, value) VALUES (?, ?)", settings.items())

    if scalar(conn, "SELECT COUNT(*) FROM mechanic_modules") == 0:
        conn.executemany(
            """
            INSERT INTO mechanic_modules
            (name, color, description, active, affects_fight, poker_enabled, visible_to_players)
            VALUES (?, ?, ?, 1, 1, 1, 1)
            """,
            [
                ("physical_power", "#ff3b3b", "Физическая мощь, давление, урон в клинче"),
                ("speed", "#22d36b", "Скорость, ловкость, реакция"),
                ("magic", "#9b4dff", "Магическая сила и аномальные техники"),
                ("intelligence", "#4aa3ff", "Интеллект, тактика, чтение боя"),
                ("media", "#ffd166", "Медийность, шум, ценность бойца"),
            ],
        )

    if scalar(conn, "SELECT COUNT(*) FROM fighters") == 0:
        fighters = [
            ("INFERNUS", "Fire Elemental", None, "PCF", "Элементаль", "Огненный боевой титан", "Pyra-9", "PCF", "Inferno District", "Мифический лавовый боец с бронёй из обсидиана и горящим ядром в груди.", "Поджигатель карда. Создан для смертельного давления и коротких разменов.", "", "", "Mythic", "", "standard", "free", 750, 1, 8, 8, 4, 4, 6, "Dark cyberpunk fantasy MMA elemental fighter, fire, lava armor, collectible toy package style, no text.", now),
            ("MORPHUS", "Psychic Ooze", None, "PCF", "Элементаль", "Психическая слизь", "Noosphere-13", "PCF", "Purple Sink", "Эпический вязкий монстр, который давит разум соперника и меняет форму тела в бою.", "Кошмар букмекеров: не держит стойку, потому что стойка держит его.", "", "", "Epic", "", "standard", "free", 650, 1, 4, 8, 3, 8, 5, "Dark cyberpunk fantasy MMA psychic ooze monster, purple aura, collectible toy package style, no text.", now),
            ("GRAVEMAW", "Bone Reactor", None, "PCF", "Некроид", "Костяной тяжеловес", "Ossuary Prime", "PCF", "White Pit", "Редкий тяжеловес из костяных пластин, медленный, но крайне прочный.", "Падает редко, ломает часто.", "", "", "Rare", "", "standard", "free", 500, 1, 7, 2, 2, 4, 3, "Dark cyberpunk fantasy undead MMA heavyweight, bone armor, neon arena, no text.", now),
            ("VEXA", "Neon Hydra", None, "PCF", "Гидра", "Мутационный страйкер", "Chrome Marsh", "PCF", "Hydra Lane", "Быстрый неоновый мутант с несколькими стилями атаки и токсичной аурой.", "Одна голова читает бой, вторая провоцирует, третья уже бьёт.", "", "", "Epic", "", "standard", "free", 620, 1, 5, 5, 8, 5, 6, "Dark cyberpunk fantasy neon hydra MMA fighter, toxic aura, mobile game character art, no text.", now),
        ]
        conn.executemany(
            """
            INSERT INTO fighters
            (name, nickname, owner_user_id, owner_status, race, creature_type, planet, country, city,
             description, alt_description, avatar_url, poster_url, rarity, title_status, contract, status,
             price, for_sale, physical_power, magic, speed, intelligence, media, prompt, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            fighters,
        )

    if scalar(conn, "SELECT COUNT(*) FROM events") == 0:
        conn.execute(
            """
            INSERT INTO events
            (title, description, announcement_date, press_date, end_date, status, random_factor,
             skill_factor, event_type, is_canon, published_on_home, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            ("PCF Neon Genesis Demo", "Тестовый кард для проверки ставок, расчёта и выплат.", now, None, None, "bets_open", 0.45, 0.55, "normal", 1, 1, now),
        )
        event_id = conn.execute("SELECT id FROM events ORDER BY id DESC LIMIT 1").fetchone()[0]
        infernus_id = conn.execute("SELECT id FROM fighters WHERE name = 'INFERNUS'").fetchone()[0]
        morphus_id = conn.execute("SELECT id FROM fighters WHERE name = 'MORPHUS'").fetchone()[0]
        conn.execute(
            """
            INSERT INTO event_fights
            (event_id, fighter_a_id, fighter_b_id, odds_a, odds_b, fight_type, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (event_id, infernus_id, morphus_id, 1.75, 2.05, "normal", "open", now),
        )


def json_loads_safe(value: str | None, default: Any = None) -> Any:
    if default is None:
        default = {}
    if not value:
        return default
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return default
