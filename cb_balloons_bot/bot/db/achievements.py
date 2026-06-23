"""Проверка и выдача достижений, чтение прогресса игрока."""
from __future__ import annotations

from db.database import connect
from game.achievements_config import ACHIEVEMENTS


def get_user_achievement_ids(user_id: int, chat_id: int) -> list[str]:
    with connect() as conn:
        rows = conn.execute(
            "SELECT achievement_id FROM user_achievements WHERE user_id = ? AND chat_id = ?",
            (user_id, chat_id),
        ).fetchall()
    return [row[0] for row in rows]


def _colors_used(game_collection: dict) -> set[str]:
    colors = set()
    if game_collection.get("blue_spheres") or game_collection.get("blue_triplets"):
        colors.add("blue")
    if game_collection.get("red_spheres") or game_collection.get("red_triplets"):
        colors.add("red")
    if (
        game_collection.get("green_spheres")
        or game_collection.get("green_triplets")
        or game_collection.get("green_nions")
    ):
        colors.add("green")
    if game_collection.get("gold_spheres"):
        colors.add("gold")
    if game_collection.get("purple_spheres") or game_collection.get("purple_triplets"):
        colors.add("purple")
    return colors


def check_achievements(user_id: int, chat_id: int, game_collection: dict) -> list[str]:
    """Возвращает имена новых достижений, начисляет очки достижений."""
    with connect() as conn:
        c = conn.cursor()
        row = c.execute(
            """
            SELECT games_played, max_points, total_points, triplets, nions, achievement_points
            FROM scores WHERE user_id = ? AND chat_id = ?
            """,
            (user_id, chat_id),
        ).fetchone()
        if not row:
            return []

        games_played, max_points, total_points, triplets, nions, _ = row
        colors_count = len(_colors_used(game_collection))
        new_achievements: list[str] = []

        already = {
            r[0]
            for r in c.execute(
                "SELECT achievement_id FROM user_achievements WHERE user_id = ? AND chat_id = ?",
                (user_id, chat_id),
            ).fetchall()
        }

        for ach in ACHIEVEMENTS:
            if ach["id"] in already:
                continue
            cond = ach["condition"]
            met = False

            if "games_played" in cond and games_played >= cond["games_played"]:
                met = True
            elif "max_game_points" in cond and max_points >= cond["max_game_points"]:
                met = True
            elif "total_game_points" in cond and total_points >= cond["total_game_points"]:
                met = True
            elif "total_triplets" in cond and triplets >= cond["total_triplets"]:
                met = True
            elif "total_nions" in cond and nions >= cond["total_nions"]:
                met = True
            elif (
                "blue_spheres_or_triplets" in cond
                and "red_spheres_or_triplets" in cond
                and "green_spheres_or_nions" in cond
                and "gold_spheres" in cond
                and "purple_spheres_or_triplets" in cond
                and colors_count == 5
            ):
                met = True
            elif (
                ("EXACTLY_4_COLORS" in cond and colors_count == 4)
                or ("EXACTLY_3_COLORS" in cond and colors_count == 3)
                or ("EXACTLY_2_COLORS" in cond and colors_count == 2)
                or ("EXACTLY_1_COLOR" in cond and colors_count == 1)
            ):
                met = True

            if met:
                c.execute(
                    "INSERT INTO user_achievements (user_id, chat_id, achievement_id) VALUES (?, ?, ?)",
                    (user_id, chat_id, ach["id"]),
                )
                c.execute(
                    "UPDATE scores SET achievement_points = achievement_points + ? WHERE user_id = ? AND chat_id = ?",
                    (ach["achievement_points"], user_id, chat_id),
                )
                new_achievements.append(ach["name"])

    return new_achievements
