from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Body, HTTPException

from .api_shared import event_by_id, fighter_by_id, fight_by_id, game_error, pack_event, settle_bets
from .engine import EngineError, calculate_fight, validate_contract, validate_event_status, validate_fight_type
from .storage import connect, get_all, get_one, utc_now

router = APIRouter(prefix="/api")


@router.post("/event")
@router.post("/admin/event")
def create_event(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    title = str(data.get("title") or data.get("name") or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Название события обязательно")

    status = str(data.get("status", "draft"))
    try:
        validate_event_status(status)
    except EngineError as exc:
        raise game_error(exc)

    with connect() as conn:
        cur = conn.execute(
            """
            INSERT INTO events
            (title, description, announcement_date, press_date, end_date, status, random_factor,
             skill_factor, event_type, is_canon, published_on_home, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                title,
                str(data.get("description", "")),
                data.get("announcement_date"),
                data.get("press_date"),
                data.get("end_date"),
                status,
                float(data.get("random_factor", 0.45)),
                float(data.get("skill_factor", 0.55)),
                str(data.get("event_type", "normal")),
                int(bool(data.get("is_canon", True))),
                int(bool(data.get("published_on_home", False))),
                utc_now(),
            ),
        )
        conn.commit()
        event = event_by_id(conn, cur.lastrowid)
        return {"ok": True, "event": pack_event(conn, event)}


@router.post("/fight")
@router.post("/admin/fight")
def create_fight(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    with connect() as conn:
        event = event_by_id(conn, int(data.get("event_id", 0)))
        fighter_a = fighter_by_id(conn, int(data.get("fighter_a_id", 0)))
        fighter_b = fighter_by_id(conn, int(data.get("fighter_b_id", 0)))
        if fighter_a["id"] == fighter_b["id"]:
            raise HTTPException(status_code=400, detail="Боец не может драться сам с собой")

        try:
            fight_type = validate_fight_type(str(data.get("fight_type", "normal")), fighter_a, fighter_b)
        except EngineError as exc:
            raise game_error(exc)

        cur = conn.execute(
            """
            INSERT INTO event_fights
            (event_id, fighter_a_id, fighter_b_id, odds_a, odds_b, fight_type, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event["id"],
                fighter_a["id"],
                fighter_b["id"],
                float(data.get("odds_a", 1.8)),
                float(data.get("odds_b", 1.8)),
                fight_type,
                str(data.get("status", "open")),
                utc_now(),
            ),
        )
        conn.commit()
        return {"ok": True, "fight": fight_by_id(conn, cur.lastrowid)}


@router.post("/calc-event")
def calc_event(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    with connect() as conn:
        event = event_by_id(conn, int(data.get("event_id", 0)))
        fights = get_all(
            conn,
            "SELECT * FROM event_fights WHERE event_id = ? AND status != 'completed' ORDER BY id",
            (event["id"],),
        )
        results = []

        for fight in fights:
            fighter_a = fighter_by_id(conn, fight["fighter_a_id"])
            fighter_b = fighter_by_id(conn, fight["fighter_b_id"])
            try:
                validate_fight_type(fight["fight_type"], fighter_a, fighter_b)
                result = calculate_fight(fighter_a, fighter_b, event["random_factor"], event["skill_factor"])
            except EngineError as exc:
                raise game_error(exc)

            conn.execute(
                """
                UPDATE event_fights
                SET winner_fighter_id = ?, result = 'completed', method = ?, round = ?,
                    admin_comment = ?, status = 'completed'
                WHERE id = ?
                """,
                (result.winner_id, result.method, result.round, f"auto probability_a={result.probability_a}", fight["id"]),
            )
            conn.execute("UPDATE fighters SET pcf_wins = pcf_wins + 1 WHERE id = ?", (result.winner_id,))
            conn.execute("UPDATE fighters SET pcf_losses = pcf_losses + 1 WHERE id = ?", (result.loser_id,))
            if fight["fight_type"] == "deadly":
                conn.execute("UPDATE fighters SET status = 'killed' WHERE id = ?", (result.loser_id,))

            bet_stats = settle_bets(conn, fight["id"], result.winner_id)
            results.append(
                {
                    "fight_id": fight["id"],
                    "winner_fighter_id": result.winner_id,
                    "loser_fighter_id": result.loser_id,
                    "method": result.method,
                    "round": result.round,
                    "probability_a": result.probability_a,
                    "bets": bet_stats,
                }
            )

        conn.execute("UPDATE events SET status = 'completed' WHERE id = ?", (event["id"],))
        conn.commit()
        return {"ok": True, "event_id": event["id"], "results": results}


@router.post("/admin/result")
def manual_result(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    with connect() as conn:
        fight = fight_by_id(conn, int(data.get("fight_id", 0)))
        winner_id = int(data.get("winner_fighter_id", 0))
        if winner_id not in (int(fight["fighter_a_id"]), int(fight["fighter_b_id"])):
            raise HTTPException(status_code=400, detail="Победитель не является участником пары")
        loser_id = fight["fighter_b_id"] if winner_id == fight["fighter_a_id"] else fight["fighter_a_id"]

        conn.execute(
            """
            UPDATE event_fights
            SET winner_fighter_id = ?, result = 'completed', method = ?, round = ?,
                admin_comment = ?, status = 'completed'
            WHERE id = ?
            """,
            (
                winner_id,
                str(data.get("method", "Decision")),
                int(data.get("round", 3)),
                str(data.get("admin_comment", "")),
                fight["id"],
            ),
        )
        conn.execute("UPDATE fighters SET pcf_wins = pcf_wins + 1 WHERE id = ?", (winner_id,))
        conn.execute("UPDATE fighters SET pcf_losses = pcf_losses + 1 WHERE id = ?", (loser_id,))
        if fight["fight_type"] == "deadly":
            conn.execute("UPDATE fighters SET status = 'killed' WHERE id = ?", (loser_id,))
        bet_stats = settle_bets(conn, fight["id"], winner_id) if data.get("settle_bets", True) else {}
        conn.commit()
        return {"ok": True, "fight": fight_by_id(conn, fight["id"]), "bets": bet_stats}


@router.post("/admin/fighter")
def create_fighter(data: dict[str, Any] = Body(...)) -> dict[str, Any]:
    name = str(data.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=400, detail="Имя бойца обязательно")
    try:
        contract = validate_contract(str(data.get("contract", "standard")))
    except EngineError as exc:
        raise game_error(exc)

    with connect() as conn:
        cur = conn.execute(
            """
            INSERT INTO fighters
            (name, nickname, owner_user_id, owner_status, race, creature_type, planet, country, city,
             description, alt_description, avatar_url, poster_url, rarity, title_status, contract, status,
             price, for_sale, physical_power, magic, speed, intelligence, media, prompt, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                name,
                str(data.get("nickname", "")),
                data.get("owner_user_id"),
                str(data.get("owner_status", "PCF")),
                str(data.get("race", "")),
                str(data.get("creature_type", "")),
                str(data.get("planet", "")),
                str(data.get("country", "")),
                str(data.get("city", "")),
                str(data.get("description", "")),
                str(data.get("alt_description", "")),
                str(data.get("avatar_url", "")),
                str(data.get("poster_url", "")),
                str(data.get("rarity", "Common")),
                str(data.get("title_status", "")),
                contract,
                str(data.get("status", "free")),
                int(data.get("price", 0)),
                int(bool(data.get("for_sale", False))),
                int(data.get("physical_power", 1)),
                int(data.get("magic", 1)),
                int(data.get("speed", 1)),
                int(data.get("intelligence", 1)),
                int(data.get("media", 0)),
                str(data.get("prompt", "")),
                utc_now(),
            ),
        )
        conn.commit()
        return {"ok": True, "fighter": fighter_by_id(conn, cur.lastrowid)}
