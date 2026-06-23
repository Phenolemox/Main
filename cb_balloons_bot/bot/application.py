"""Сборка Telegram-приложения CB Balloons и точка входа для polling."""
from __future__ import annotations

import logging

from telegram import BotCommand
from telegram.ext import (
    ApplicationBuilder,
    CallbackQueryHandler,
    CommandHandler,
    Defaults,
    MessageHandler,
    filters,
)

from bot_config import TOKEN
from db.database import init_db
from handlers import callbacks, commands

log = logging.getLogger("cb_balloons_bot")

BOT_COMMANDS = [
    BotCommand("start", "Начать работу с ботом"),
    BotCommand("menu", "Главное меню"),
    BotCommand("ball", "Начать новую игру"),
    BotCommand("stats", "Твоя статистика"),
    BotCommand("achievements", "Показать достижения"),
    BotCommand("how", "Как играть"),
    BotCommand("reset", "Сбросить результаты (админ)"),
]


def build_application():
    if not TOKEN:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is not configured")
    init_db()
    app = ApplicationBuilder().token(TOKEN).defaults(Defaults(parse_mode="HTML")).build()

    app.add_handler(CommandHandler("start", commands.start))
    app.add_handler(CommandHandler("menu", commands.menu))
    app.add_handler(CommandHandler("help", commands.help_command))
    app.add_handler(CommandHandler("ball", commands.ball))
    app.add_handler(CommandHandler("stats", commands.stats))
    app.add_handler(CommandHandler("achievements", commands.achievements))
    app.add_handler(CommandHandler("how", commands.how))
    app.add_handler(CommandHandler("reset", commands.reset))
    app.add_handler(CallbackQueryHandler(callbacks.button_handler))
    app.add_handler(MessageHandler(filters.PHOTO, commands.get_photo_id))
    return app


async def configure_commands(application) -> None:
    await application.bot.set_my_commands(BOT_COMMANDS)


async def main() -> None:
    app = build_application()
    await configure_commands(app)
    log.info("Сферы созданы — CB Balloons запущен")
    await app.run_polling()


if __name__ == "__main__":
    import asyncio

    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
