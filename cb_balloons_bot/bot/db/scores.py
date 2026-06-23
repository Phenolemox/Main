"""Запись и чтение игровых очков."""
from __future__ import annotations

from db.database import connect, now_iso


def update_scores(
    user_id: int,
    username: str | None,
    chat_id: int,
    points: int,
    triplets: int,
    nions: int,
    sphere_counts: dict,
    triplet_counts: dict,
    nions_counts: dict,
) -> None:
    """Сохраняет результат партии (upsert по user_id+chat_id)."""
    now = now_iso()
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO scores (
                user_id, username, chat_id, points, last_play, games_played, max_points, total_points,
                triplets, nions,
                blue_spheres, red_spheres, green_spheres, gold_spheres, purple_spheres,
                blue_triplets, red_triplets, green_triplets, purple_triplets, green_nions
            )
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, chat_id) DO UPDATE SET
                points = ?,
                username = ?,
                last_play = ?,
                games_played = games_played + 1,
                max_points = MAX(max_points, ?),
                total_points = total_points + ?,
                triplets = triplets + ?,
                nions = nions + ?,
                blue_spheres = blue_spheres + ?, red_spheres = red_spheres + ?,
                green_spheres = green_spheres + ?, gold_spheres = gold_spheres + ?,
                purple_spheres = purple_spheres + ?,
                blue_triplets = blue_triplets + ?, red_triplets = red_triplets + ?,
                green_triplets = green_triplets + ?, purple_triplets = purple_triplets + ?,
                green_nions = green_nions + ?
            """,
            (
                user_id, username, chat_id, points, now,
                points, points, triplets, nions,
                sphere_counts["blue"], sphere_counts["red"], sphere_counts["green"],
                sphere_counts["gold"], sphere_counts["purple"],
                triplet_counts["blue"], triplet_counts["red"], triplet_counts["green"],
                triplet_counts["purple"], nions_counts["green"],
                # UPDATE-ветка
                points, username, now,
                points, points, triplets, nions,
                sphere_counts["blue"], sphere_counts["red"], sphere_counts["green"],
                sphere_counts["gold"], sphere_counts["purple"],
                triplet_counts["blue"], triplet_counts["red"], triplet_counts["green"],
                triplet_counts["purple"], nions_counts["green"],
            ),
        )


def get_player_stats(user_id: int, chat_id: int) -> tuple | None:
    with connect() as conn:
        return conn.execute(
            """
            SELECT games_played, max_points, total_points, triplets, nions, achievement_points
            FROM scores WHERE chat_id = ? AND user_id = ?
            """,
            (chat_id, user_id),
        ).fetchone()


def reset_chat(chat_id: int) -> None:
    with connect() as conn:
        conn.execute("DELETE FROM scores WHERE chat_id = ?", (chat_id,))
        conn.execute("DELETE FROM user_achievements WHERE chat_id = ?", (chat_id,))
