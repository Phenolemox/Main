from __future__ import annotations

import json
import os
from datetime import datetime, timedelta
from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query

from .api_shared import event_by_id, fighter_by_id, fight_by_id, pack_event, settings, user_by_id
from .engine import TRAINABLE_STATS, validate_contract
from .storage import connect, get_all, get_one, scalar, utc_now

router = APIRouter(prefix="/api")

STAT_UPDATE_SQL = {
    "physical_power": "UPDATE fighters SET physical_power = physical_power + 1, status = 'free' WHERE id = ?",
    "magic": "UPDATE fighters SET magic = magic + 1, status = 'free' WHERE id = ?",
    "speed": "UPDATE fighters SET speed = speed + 1, status = 'free' WHERE id = ?",
    "intelligence": "UPDATE fighters SET intelligence = intelligence + 1, status = 'free' WHERE id = ?",
    "media": "UPDATE fighters SET media = media + 1, status = 'free' WHERE id = ?",
}


@router.post("/login")
def login(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    username = str(data.get("username", ""))
    password = str(data.get("password", ""))
    with connect() as conn:
        user = get_one(conn, "SELECT * FROM users WHERE username = ? AND password = ?", (username, password))
        if user is None:
            raise HTTPException(status_code=401, detail="Неверный логин или пароль")
        return {"ok": True, "user": user}


@router.get("/state")
def state(user_id: int = Query(default=2)) -> dict[str, Any]:
    with connect() as conn:
        events = [pack_event(conn, event) for event in get_all(conn, "SELECT * FROM events ORDER BY id DESC")]
        return {
            "ok": True,
            "user": get_one(conn, "SELECT * FROM users WHERE id = ?", (user_id,)),
            "settings": settings(conn),
            "fighters": get_all(conn, "SELECT * FROM fighters ORDER BY id DESC"),
            "my_fighters": get_all(conn, "SELECT * FROM fighters WHERE owner_user_id = ? ORDER BY id DESC", (user_id,)),
            "market": get_all(conn, "SELECT * FROM fighters WHERE for_sale = 1 AND owner_status = 'PCF' ORDER BY price ASC, id DESC"),
            "events": events,
            "bets": get_all(
                conn,
                """
                SELECT b.*, f.name AS chosen_fighter_name, e.title AS event_title
                FROM bets b
                JOIN fighters f ON f.id = b.chosen_fighter_id
                JOIN events e ON e.id = b.event_id
                WHERE b.user_id = ?
                ORDER BY b.id DESC
                """,
                (user_id,),
            ),
            "training_sessions": get_all(
                conn,
                """
                SELECT ts.*, f.name AS fighter_name
                FROM training_sessions ts
                JOIN fighters f ON f.id = ts.fighter_id
                WHERE ts.user_id = ?
                ORDER BY ts.id DESC
                """,
                (user_id,),
            ),
        }


@router.post("/bet")
def place_bet(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    amount = int(data.get("amount", 0))
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Сумма ставки должна быть больше нуля")

    with connect() as conn:
        user = user_by_id(conn, int(data.get("user_id", 0)))
        event = event_by_id(conn, int(data.get("event_id", 0)))
        fight = fight_by_id(conn, int(data.get("fight_id", 0)))
        chosen_fighter_id = int(data.get("chosen_fighter_id", 0))
        cfg = settings(conn)

        if cfg.get("bets_enabled", "1") != "1":
            raise HTTPException(status_code=403, detail="Ставки выключены")
        if event["status"] != "bets_open" or fight["status"] != "open":
            raise HTTPException(status_code=400, detail="Ставки на этот бой закрыты")
        if int(fight["event_id"]) != int(event["id"]):
            raise HTTPException(status_code=400, detail="Пара не относится к событию")
        if chosen_fighter_id not in (int(fight["fighter_a_id"]), int(fight["fighter_b_id"])):
            raise HTTPException(status_code=400, detail="Выбран не участник пары")
        if int(user["balance"]) < amount:
            raise HTTPException(status_code=400, detail="Недостаточно баланса")

        odds = fight["odds_a"] if chosen_fighter_id == int(fight["fighter_a_id"]) else fight["odds_b"]
        payout = int(round(amount * float(odds)))

        conn.execute("UPDATE users SET balance = balance - ? WHERE id = ?", (amount, user["id"]))
        if not user["first_bet_done"]:
            bonus = int(cfg.get("first_bet_bonus", "300"))
            conn.execute("UPDATE users SET first_bet_done = 1, balance = balance + ? WHERE id = ?", (bonus, user["id"]))

        cur = conn.execute(
            """
            INSERT INTO bets
            (user_id, event_id, fight_id, chosen_fighter_id, amount, odds, potential_payout, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?)
            """,
            (user["id"], event["id"], fight["id"], chosen_fighter_id, amount, odds, payout, utc_now()),
        )
        conn.commit()
        return {
            "ok": True,
            "bet": get_one(conn, "SELECT * FROM bets WHERE id = ?", (cur.lastrowid,)),
            "user": user_by_id(conn, user["id"]),
        }


@router.post("/claim-first-fighter")
def claim_first_fighter(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    contract = validate_contract(str(data.get("contract", "standard")))
    with connect() as conn:
        user = user_by_id(conn, int(data.get("user_id", 0)))
        if not user["first_bet_done"]:
            raise HTTPException(status_code=400, detail="Первый боец открывается после первой ставки")
        if user["first_fighter_claimed"]:
            raise HTTPException(status_code=400, detail="Первый боец уже получен")

        if data.get("fighter_id"):
            fighter = fighter_by_id(conn, int(data["fighter_id"]))
        else:
            fighter = get_one(conn, "SELECT * FROM fighters WHERE owner_status = 'PCF' AND for_sale = 1 ORDER BY price ASC LIMIT 1")

        if fighter is None or fighter["owner_status"] != "PCF" or not fighter["for_sale"]:
            raise HTTPException(status_code=400, detail="Боец недоступен")

        conn.execute(
            """
            UPDATE fighters
            SET owner_user_id = ?, owner_status = 'player', contract = ?, for_sale = 0, status = 'free'
            WHERE id = ?
            """,
            (user["id"], contract, fighter["id"]),
        )
        conn.execute("UPDATE users SET first_fighter_claimed = 1 WHERE id = ?", (user["id"],))
        conn.commit()
        return {"ok": True, "fighter": fighter_by_id(conn, fighter["id"]), "user": user_by_id(conn, user["id"])}


@router.post("/market-buy")
def market_buy(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    with connect() as conn:
        cfg = settings(conn)
        if cfg.get("market_enabled", "1") != "1":
            raise HTTPException(status_code=403, detail="Рынок выключен")
        user = user_by_id(conn, int(data.get("user_id", 0)))
        fighter = fighter_by_id(conn, int(data.get("fighter_id", 0)))
        if not fighter["for_sale"] or fighter["owner_status"] != "PCF":
            raise HTTPException(status_code=400, detail="Боец не продаётся")
        if int(user["balance"]) < int(fighter["price"]):
            raise HTTPException(status_code=400, detail="Недостаточно баланса")
        conn.execute("UPDATE users SET balance = balance - ? WHERE id = ?", (fighter["price"], user["id"]))
        conn.execute(
            "UPDATE fighters SET owner_user_id = ?, owner_status = 'player', for_sale = 0 WHERE id = ?",
            (user["id"], fighter["id"]),
        )
        conn.commit()
        return {"ok": True, "fighter": fighter_by_id(conn, fighter["id"]), "user": user_by_id(conn, user["id"])}


@router.post("/train")
def start_training(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    stat = str(data.get("stat", ""))
    if stat not in TRAINABLE_STATS:
        raise HTTPException(status_code=400, detail="Недопустимая характеристика")

    with connect() as conn:
        cfg = settings(conn)
        if cfg.get("training_enabled", "1") != "1":
            raise HTTPException(status_code=403, detail="Тренировки выключены")
        user = user_by_id(conn, int(data.get("user_id", 0)))
        fighter = fighter_by_id(conn, int(data.get("fighter_id", 0)))
        if fighter["owner_user_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Можно тренировать только своего бойца")
        if fighter["status"] in ("dead", "killed", "retired"):
            raise HTTPException(status_code=400, detail="Этот боец не может тренироваться")
        active_count = scalar(conn, "SELECT COUNT(*) FROM training_sessions WHERE fighter_id = ? AND status = 'active'", (fighter["id"],))
        if active_count:
            raise HTTPException(status_code=400, detail="Боец уже на тренировке")

        seconds = int(cfg.get("training_seconds", os.getenv("PCF_TRAINING_SECONDS", "30")))
        started = datetime.utcnow().replace(microsecond=0)
        finish = started + timedelta(seconds=seconds)
        cur = conn.execute(
            """
            INSERT INTO training_sessions
            (user_id, fighter_id, stat, started_at, finish_at, status, result_json)
            VALUES (?, ?, ?, ?, ?, 'active', '{}')
            """,
            (user["id"], fighter["id"], stat, started.isoformat(), finish.isoformat()),
        )
        conn.execute("UPDATE fighters SET status = 'training' WHERE id = ?", (fighter["id"],))
        conn.commit()
        return {"ok": True, "training": get_one(conn, "SELECT * FROM training_sessions WHERE id = ?", (cur.lastrowid,))}


@router.post("/finish-training/{training_id}")
def finish_training(training_id: int, user_id: int = Query(...)) -> dict[str, Any]:
    with connect() as conn:
        user = user_by_id(conn, user_id)
        session = get_one(conn, "SELECT * FROM training_sessions WHERE id = ?", (training_id,))
        if session is None:
            raise HTTPException(status_code=404, detail="Тренировка не найдена")
        if session["user_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Это не твоя тренировка")
        if session["status"] != "active":
            raise HTTPException(status_code=400, detail="Тренировка уже завершена")
        if datetime.utcnow() < datetime.fromisoformat(session["finish_at"]):
            raise HTTPException(status_code=400, detail="Тренировка ещё не завершена")

        stat = session["stat"]
        update_sql = STAT_UPDATE_SQL.get(stat)
        if update_sql is None:
            raise HTTPException(status_code=400, detail="Недопустимая характеристика")

        result = {"stat": stat, "bonus": 1, "mode": "basic_training"}
        conn.execute(update_sql, (session["fighter_id"],))
        conn.execute(
            "UPDATE training_sessions SET status = 'completed', result_json = ? WHERE id = ?",
            (json.dumps(result, ensure_ascii=False), session["id"]),
        )
        conn.commit()
        return {"ok": True, "result": result, "fighter": fighter_by_id(conn, session["fighter_id"])}
