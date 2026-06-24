from __future__ import annotations

from typing import Any

from fastapi import HTTPException

from .engine import EngineError
from .storage import get_all, get_one


def game_error(exc: Exception) -> HTTPException:
    status = 400 if isinstance(exc, EngineError) else 500
    return HTTPException(status_code=status, detail=str(exc))


def settings(conn) -> dict[str, str]:
    rows = get_all(conn, "SELECT key, value FROM settings ORDER BY key")
    return {row["key"]: row["value"] for row in rows}


def user_by_id(conn, user_id: int) -> dict[str, Any]:
    user = get_one(conn, "SELECT * FROM users WHERE id = ?", (user_id,))
    if user is None:
        raise HTTPException(status_code=404, detail="Игрок не найден")
    return user


def fighter_by_id(conn, fighter_id: int) -> dict[str, Any]:
    fighter = get_one(conn, "SELECT * FROM fighters WHERE id = ?", (fighter_id,))
    if fighter is None:
        raise HTTPException(status_code=404, detail="Боец не найден")
    return fighter


def event_by_id(conn, event_id: int) -> dict[str, Any]:
    event = get_one(conn, "SELECT * FROM events WHERE id = ?", (event_id,))
    if event is None:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    return event


def fight_by_id(conn, fight_id: int) -> dict[str, Any]:
    fight = get_one(conn, "SELECT * FROM event_fights WHERE id = ?", (fight_id,))
    if fight is None:
        raise HTTPException(status_code=404, detail="Пара не найдена")
    return fight


def pack_event(conn, event: dict[str, Any]) -> dict[str, Any]:
    event["fights"] = get_all(
        conn,
        """
        SELECT ef.*,
               fa.name AS fighter_a_name,
               fa.nickname AS fighter_a_nickname,
               fa.rarity AS fighter_a_rarity,
               fa.physical_power AS fighter_a_power,
               fa.magic AS fighter_a_magic,
               fa.speed AS fighter_a_speed,
               fa.intelligence AS fighter_a_intelligence,
               fa.media AS fighter_a_media,
               fb.name AS fighter_b_name,
               fb.nickname AS fighter_b_nickname,
               fb.rarity AS fighter_b_rarity,
               fb.physical_power AS fighter_b_power,
               fb.magic AS fighter_b_magic,
               fb.speed AS fighter_b_speed,
               fb.intelligence AS fighter_b_intelligence,
               fb.media AS fighter_b_media
        FROM event_fights ef
        JOIN fighters fa ON fa.id = ef.fighter_a_id
        JOIN fighters fb ON fb.id = ef.fighter_b_id
        WHERE ef.event_id = ?
        ORDER BY ef.id DESC
        """,
        (event["id"],),
    )
    return event


def settle_bets(conn, fight_id: int, winner_fighter_id: int) -> dict[str, int]:
    stats = {"won": 0, "lost": 0, "paid": 0}
    bets = get_all(conn, "SELECT * FROM bets WHERE fight_id = ? AND status = 'active'", (fight_id,))
    for bet in bets:
        if int(bet["chosen_fighter_id"]) == int(winner_fighter_id):
            conn.execute("UPDATE bets SET status = 'won' WHERE id = ?", (bet["id"],))
            conn.execute("UPDATE users SET balance = balance + ? WHERE id = ?", (bet["potential_payout"], bet["user_id"]))
            stats["won"] += 1
            stats["paid"] += int(bet["potential_payout"])
        else:
            conn.execute("UPDATE bets SET status = 'lost' WHERE id = ?", (bet["id"],))
            stats["lost"] += 1
    return stats
