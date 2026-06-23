"""Все пользовательские тексты бота CB Balloons (RU)."""
from __future__ import annotations

from bot_config import TOTAL_ROUNDS


def welcome(first_name: str) -> str:
    return (
        f"✨ <b>Добро пожаловать, {first_name}!</b>\n"
        "Это <b>Мастер сфер</b> — собери идеальную комбинацию за "
        f"{TOTAL_ROUNDS} раундов.\n\n"
        "Нажми «🎮 Играть» в меню ниже или отправь /ball."
    )


MENU_TITLE = (
    "🔮 <b>Мастер сфер — меню</b>\n\n"
    "Выбирай сферы, собирай триплеты и нионсы, открывай достижения "
    "и поднимайся по званиям. Что делаем?"
)

HELP = (
    "📜 <b>Команды бота</b>\n\n"
    "/start — запустить бота\n"
    "/menu — главное меню\n"
    "/ball — начать новую игру\n"
    "/stats — твоя статистика\n"
    "/achievements — достижения\n"
    "/how — как играть\n"
    "/reset — сбросить результаты (в группе — админ)"
)

HOW_CAPTION = "🔮 <b>Правила игры</b>"

ALREADY_PLAYED = "🕒 Сегодня вы уже играли. Возвращайтесь завтра!"
NOT_YOUR_GAME = "Это не ваша игра!"
GAME_NOT_FOUND = "Игра не найдена. Начните новую: /ball"
PICK_REQUIRED = "Выберите нужное количество сфер!"
RESET_PRIVATE = "🔄 Ваши очки и достижения сброшены."
RESET_GROUP = "🔄 Очки и достижения всех игроков в этом чате сброшены!"
RESET_NO_RIGHTS = "⛔ У вас нет прав на сброс результатов в группе."
NO_GAMES_YET = "🕹 Ты ещё не сыграл ни одной игры. Жми /ball!"
GAME_OVER_TITLE = "🎉 <b>Игра окончена!</b>"
ERROR_GENERIC = "⚠️ Произошла ошибка при подсчёте. Попробуйте сыграть ещё раз: /ball"


def max_picks(pick_count: int) -> str:
    return f"Максимум {pick_count} сфер!"


def round_header(round_num: int, collection_text: str, pick_num: int, offer_num: int) -> str:
    return (
        f"🎯 <b>Раунд {round_num}/{TOTAL_ROUNDS}</b>\n\n"
        f"{collection_text}\n\n"
        f"Выберите <b>{pick_num}</b> из {offer_num}:"
    )
