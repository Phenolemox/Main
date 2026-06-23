"""Построение inline-клавиатур: меню, навигация и игровое поле."""
from __future__ import annotations

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo

from bot_config import MAX_APP_URL, MINI_APP_URL


def app_buttons() -> list[list[InlineKeyboardButton]]:
    rows: list[list[InlineKeyboardButton]] = []
    if MINI_APP_URL:
        rows.append([InlineKeyboardButton("📱 Mini App", web_app=WebAppInfo(url=MINI_APP_URL))])
    if MAX_APP_URL:
        rows.append([InlineKeyboardButton("🟣 Открыть в MAX", url=MAX_APP_URL)])
    return rows


def main_menu() -> InlineKeyboardMarkup:
    rows = [
        [InlineKeyboardButton("🎮 Играть", callback_data="menu_play")],
        [
            InlineKeyboardButton("📊 Статистика", callback_data="menu_stats"),
            InlineKeyboardButton("🏅 Достижения", callback_data="menu_ach"),
        ],
        [InlineKeyboardButton("❓ Как играть", callback_data="menu_how")],
    ]
    rows.extend(app_buttons())
    return InlineKeyboardMarkup(rows)


def start_menu() -> InlineKeyboardMarkup:
    rows = [[InlineKeyboardButton("🎮 Играть", callback_data="menu_play")]]
    rows.extend(app_buttons())
    rows.append([InlineKeyboardButton("📋 Меню", callback_data="menu_open")])
    return InlineKeyboardMarkup(rows)


def back_to_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton("⬅️ В меню", callback_data="menu_open")]]
    )


def offer_keyboard(user_id: int, offer: list[str], selected: list[int]) -> InlineKeyboardMarkup:
    buttons = [
        InlineKeyboardButton(
            ("✅ " if i in selected else f"{i + 1}. ") + ball,
            callback_data=f"toggle_{user_id}_{i}",
        )
        for i, ball in enumerate(offer)
    ]
    layout = [buttons[i:i + 5] for i in range(0, len(buttons), 5)]
    layout.append([InlineKeyboardButton("✅ Принять", callback_data=f"accept_{user_id}")])
    layout.append([InlineKeyboardButton("🚫 Завершить", callback_data=f"quit_{user_id}")])
    return InlineKeyboardMarkup(layout)


def after_game() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [InlineKeyboardButton("🔁 Сыграть ещё", callback_data="menu_play")],
            [InlineKeyboardButton("📋 Меню", callback_data="menu_open")],
        ]
    )
