"""Обработчики команд бота."""
from __future__ import annotations

from telegram import Update
from telegram.ext import ContextTypes

import texts
from bot_config import BOSS_ID, HOW_PHOTO_FILE_ID
from db.achievements import get_user_achievement_ids
from db.database import save_user
from db.scores import get_player_stats, reset_chat
from game.achievements_config import ACHIEVEMENTS, RANKS
from game.session import clear_chat_sessions
from handlers.game_flow import begin_game
from keyboards.game import back_to_menu, main_menu, start_menu


def _chat_scope(update: Update) -> int:
    chat = update.effective_chat
    return update.effective_user.id if chat.type == "private" else chat.id


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    save_user(user.id, user.username)
    await update.message.reply_text(
        texts.welcome(user.first_name),
        reply_markup=start_menu(),
        parse_mode="HTML",
    )


async def menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        texts.MENU_TITLE, reply_markup=main_menu(), parse_mode="HTML"
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(texts.HELP, reply_markup=back_to_menu(), parse_mode="HTML")


async def how(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    try:
        await update.message.reply_photo(
            photo=HOW_PHOTO_FILE_ID, caption=texts.HOW_CAPTION, parse_mode="HTML"
        )
    except Exception:  # noqa: BLE001 — file_id может протухнуть
        await update.message.reply_text(texts.HOW_CAPTION, parse_mode="HTML")


def stats_text(user_id: int, chat_id: int) -> str:
    data = get_player_stats(user_id, chat_id)
    achieved = get_user_achievement_ids(user_id, chat_id)
    if not data:
        return texts.NO_GAMES_YET
    games_played, max_points, total_points, triplets, nions, ach_points = data
    rank = next(
        (r["title"] for r in RANKS if r["min_achievement_points"] <= ach_points <= r["max_achievement_points"]),
        "Новичок",
    )
    return (
        f"🎖 <b>Звание:</b> {rank}\n\n"
        f"🎲 Сыграно партий: {games_played}\n"
        f"🏅 Максимально очков: {max_points}\n"
        f"💎 Всего очков: {total_points}\n"
        f"🔮 Триплетов: {triplets}\n"
        f"✨ Нионсов: {nions}\n\n"
        f"🏆 Очки достижений: {ach_points}\n"
        f"📜 Выполненные достижения: {len(achieved)}/{len(ACHIEVEMENTS)}"
    )


async def stats(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = stats_text(update.effective_user.id, _chat_scope(update))
    await update.message.reply_text(text, reply_markup=back_to_menu(), parse_mode="HTML")


def achievements_text(user_id: int, chat_id: int) -> str:
    achieved = set(get_user_achievement_ids(user_id, chat_id))
    lines = ["<b>🏅 Твои достижения:</b>\n"]
    for ach in ACHIEVEMENTS:
        mark = "✅" if ach["id"] in achieved else "❌"
        lines.append(
            f"{mark} <b>{ach['name']}</b> (+{ach['achievement_points']} очков) — {ach['description']}"
        )
    return "\n".join(lines)


async def achievements(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = achievements_text(update.effective_user.id, _chat_scope(update))
    await update.message.reply_text(text, reply_markup=back_to_menu(), parse_mode="HTML")


async def ball(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await begin_game(context, update.effective_user, update.effective_chat)


async def reset(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    chat = update.effective_chat
    save_user(user.id, user.username)

    if chat.type == "private":
        reset_chat(chat.id)
        clear_chat_sessions(chat.id)
        await update.message.reply_text(texts.RESET_PRIVATE)
        return

    if user.id != BOSS_ID:
        await update.message.reply_text(texts.RESET_NO_RIGHTS)
        return

    reset_chat(chat.id)
    clear_chat_sessions(chat.id)
    await update.message.reply_text(texts.RESET_GROUP)


async def get_photo_id(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message and update.message.photo:
        file_id = update.message.photo[-1].file_id
        await update.message.reply_text(
            f"📸 File ID картинки:\n\n<code>{file_id}</code>", parse_mode="HTML"
        )
