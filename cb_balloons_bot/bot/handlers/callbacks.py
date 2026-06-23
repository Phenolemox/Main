"""Единый обработчик callback-кнопок (меню + игровое поле).

Ключевое исправление зависания: callback-запрос подтверждается СРАЗУ
(query.answer), а вся игровая логика обёрнута так, что исключения не «вешают»
кнопку, а приводят к понятному сообщению.
"""
from __future__ import annotations

import logging

from telegram import Update
from telegram.error import BadRequest, NetworkError
from telegram.ext import ContextTypes

import texts
from bot_config import HOW_PHOTO_FILE_ID
from game.session import end_session, get_session
from handlers.commands import achievements_text, stats_text
from handlers.game_flow import begin_game, finish_game, render_round
from keyboards.game import back_to_menu, main_menu, offer_keyboard

log = logging.getLogger("cb_balloons_bot.callbacks")


async def _safe_answer(query, text: str | None = None, alert: bool = False) -> None:
    try:
        await query.answer(text=text, show_alert=alert)
    except NetworkError:
        pass


def _scope(query, user_id: int) -> int:
    chat = query.message.chat
    return user_id if chat.type == "private" else chat.id


async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    data = query.data or ""
    user_id = query.from_user.id

    # 1) Подтверждаем callback сразу — кнопка перестаёт «крутиться».
    if not data.startswith(("toggle_", "accept_")):
        await _safe_answer(query)

    try:
        if data.startswith("menu_"):
            await _handle_menu(query, context, data, user_id)
        elif data.startswith("toggle_"):
            await _handle_toggle(query, data, user_id)
        elif data.startswith("accept_"):
            await _handle_accept(query, data, user_id)
        elif data.startswith("quit_"):
            await _handle_quit(query, data, user_id)
    except BadRequest as exc:
        # «Message is not modified» и подобное — не критично.
        if "not modified" not in str(exc).lower():
            log.warning("BadRequest в callback %s: %s", data, exc)
    except Exception:  # noqa: BLE001
        log.exception("Ошибка обработки callback %s", data)
        await _safe_answer(query, texts.ERROR_GENERIC, alert=True)


async def _handle_menu(query, context, data: str, user_id: int) -> None:
    chat = query.message.chat
    scope = _scope(query, user_id)

    if data == "menu_open":
        await query.edit_message_text(texts.MENU_TITLE, reply_markup=main_menu(), parse_mode="HTML")
    elif data == "menu_play":
        await begin_game(context, query.from_user, chat)
    elif data == "menu_stats":
        await query.edit_message_text(
            stats_text(user_id, scope), reply_markup=back_to_menu(), parse_mode="HTML"
        )
    elif data == "menu_ach":
        await query.edit_message_text(
            achievements_text(user_id, scope), reply_markup=back_to_menu(), parse_mode="HTML"
        )
    elif data == "menu_how":
        try:
            await context.bot.send_photo(
                chat.id, photo=HOW_PHOTO_FILE_ID, caption=texts.HOW_CAPTION, parse_mode="HTML"
            )
        except Exception:  # noqa: BLE001
            await context.bot.send_message(chat.id, texts.HOW_CAPTION, parse_mode="HTML")


async def _handle_toggle(query, data: str, user_id: int) -> None:
    _, game_user_id_str, index_str = data.split("_")
    game_user_id, index = int(game_user_id_str), int(index_str)

    if user_id != game_user_id:
        await _safe_answer(query, texts.NOT_YOUR_GAME, alert=True)
        return

    session = get_session(game_user_id)
    if not session:
        await _safe_answer(query, texts.GAME_NOT_FOUND, alert=True)
        return

    status = session.toggle(index)
    if status == "full":
        await _safe_answer(query, texts.max_picks(session.pick_count), alert=True)
        return

    await _safe_answer(query)
    await query.edit_message_reply_markup(
        offer_keyboard(game_user_id, session.offer, session.selected)
    )


async def _handle_accept(query, data: str, user_id: int) -> None:
    _, game_user_id_str = data.split("_")
    game_user_id = int(game_user_id_str)

    if user_id != game_user_id:
        await _safe_answer(query, texts.NOT_YOUR_GAME, alert=True)
        return

    session = get_session(game_user_id)
    if not session:
        await _safe_answer(query, texts.GAME_NOT_FOUND, alert=True)
        return

    if not session.selection_complete():
        await _safe_answer(query, texts.PICK_REQUIRED, alert=True)
        return

    await _safe_answer(query)
    session.commit_selection()

    if not session.is_last_round:
        session.advance_round()
        await render_round(query, session, game_user_id)
    else:
        await finish_game(query, session, game_user_id, query.from_user.username)


async def _handle_quit(query, data: str, user_id: int) -> None:
    _, game_user_id_str = data.split("_")
    game_user_id = int(game_user_id_str)
    if user_id != game_user_id:
        await _safe_answer(query, texts.NOT_YOUR_GAME, alert=True)
        return
    end_session(game_user_id)
    await query.edit_message_text(
        "🚫 Игра завершена. Начать новую: /ball", reply_markup=back_to_menu()
    )
