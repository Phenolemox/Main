"""Общая игровая логика: старт партии, отрисовка раунда, финал."""
from __future__ import annotations

import logging

from telegram.ext import ContextTypes

import texts
from db.achievements import check_achievements
from db.database import already_played_today, save_user, touch_last_play
from db.scores import update_scores
from game.scoring import breakdown_collection, calculate_score, display_balloon_collection
from game.session import GameSession, end_session, start_session
from keyboards.game import after_game, offer_keyboard

log = logging.getLogger("cb_balloons_bot.flow")


def resolve_chat_id(session: GameSession, user_id: int) -> int:
    return user_id if session.private else session.chat_id


async def begin_game(context: ContextTypes.DEFAULT_TYPE, user, chat) -> None:
    """Создаёт новую партию и отправляет сообщение раунда 1."""
    save_user(user.id, user.username)
    is_private = chat.type == "private"

    if not is_private and already_played_today(user.id, chat.id):
        await context.bot.send_message(chat.id, texts.ALREADY_PLAYED)
        return

    session = start_session(user.id, chat.id, is_private)
    touch_last_play(user.id, chat.id)

    offer_num = len(session.offer)
    text = texts.round_header(
        session.round,
        display_balloon_collection(session.collection),
        session.pick_count,
        offer_num,
    )
    await context.bot.send_message(
        chat.id,
        text,
        reply_markup=offer_keyboard(user.id, session.offer, session.selected),
        parse_mode="HTML",
    )


async def render_round(query, session: GameSession, user_id: int) -> None:
    offer_num = len(session.offer)
    text = texts.round_header(
        session.round,
        display_balloon_collection(session.collection),
        session.pick_count,
        offer_num,
    )
    await query.edit_message_text(
        text,
        reply_markup=offer_keyboard(user_id, session.offer, session.selected),
        parse_mode="HTML",
    )


async def finish_game(query, session: GameSession, user_id: int, username: str | None) -> None:
    """Финальный подсчёт. Любая ошибка отлавливается, чтобы кнопка не «зависала»."""
    try:
        details_text, total_points = calculate_score(session.collection)
        agg = breakdown_collection(session.collection)
        chat_id = resolve_chat_id(session, user_id)

        update_scores(
            user_id,
            username,
            chat_id,
            total_points,
            agg["triplets_total"],
            agg["nions_total"],
            agg["sphere_counts"],
            agg["triplet_counts"],
            agg["nions_counts"],
        )

        await query.edit_message_text(
            f"{texts.GAME_OVER_TITLE}\n\n{details_text}",
            reply_markup=after_game(),
            parse_mode="HTML",
        )

        game_collection_counts = {
            "blue_spheres": agg["sphere_counts"]["blue"],
            "red_spheres": agg["sphere_counts"]["red"],
            "green_spheres": agg["sphere_counts"]["green"],
            "gold_spheres": agg["sphere_counts"]["gold"],
            "purple_spheres": agg["sphere_counts"]["purple"],
            "blue_triplets": agg["triplet_counts"]["blue"],
            "red_triplets": agg["triplet_counts"]["red"],
            "green_triplets": agg["triplet_counts"]["green"],
            "purple_triplets": agg["triplet_counts"]["purple"],
            "green_nions": agg["nions_counts"]["green"],
        }
        new_achievements = check_achievements(user_id, chat_id, game_collection_counts)
        if new_achievements:
            await query.message.reply_text(
                "✨ <b>Новые достижения:</b>\n- " + "\n- ".join(new_achievements),
                parse_mode="HTML",
            )
    except Exception:  # noqa: BLE001 — показываем игроку сообщение вместо зависания
        log.exception("Ошибка при завершении партии (user_id=%s)", user_id)
        with_suppress_edit = getattr(query, "edit_message_text", None)
        if with_suppress_edit:
            try:
                await query.edit_message_text(texts.ERROR_GENERIC, reply_markup=after_game())
            except Exception:  # noqa: BLE001
                pass
    finally:
        end_session(user_id)
