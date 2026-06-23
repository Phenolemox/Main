import os
import random, datetime, sqlite3
import sys
from zoneinfo import ZoneInfo
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand, WebAppInfo
from telegram.request import HTTPXRequest

# Настраиваем увеличенные таймауты (в секундах)
request = HTTPXRequest(connect_timeout=10.0, read_timeout=20.0)


from telegram.ext import ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes
from plates_config import license_plates
# Быстрый доступ по типу комбинации
import nest_asyncio
import logging
from telegram.error import Forbidden, TimedOut, NetworkError

if sys.platform.startswith('win'):
    nest_asyncio.apply()

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
DB_FILE = os.getenv("DB_FILE", "autobot.db")
OWNER_ID = int(os.getenv("OWNER_ID", "484184861"))
MINI_APP_URL = os.getenv("TELEGRAM_MINI_APP_URL", "").strip()
MAX_APP_URL = os.getenv("MAX_APP_URL", "").strip()

# --- Вспомогательные функции ---

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS players (
        user_id INTEGER,
        username TEXT,
        chat_id INTEGER,
        total_points INTEGER DEFAULT 0,
        best_points INTEGER DEFAULT 0,
        best_plate TEXT,
        current_plate TEXT,
        current_points INTEGER DEFAULT 0,
        has_exchanged INTEGER DEFAULT 0,
        last_played TEXT,
        PRIMARY KEY (user_id, chat_id)
    )
    """)
    conn.commit()
    conn.close()


def save_player(user_id, username, chat_id):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("""
    INSERT OR IGNORE INTO players (user_id, username, chat_id) VALUES (?, ?, ?)
    """, (user_id, username, chat_id))
    conn.commit()
    conn.close()

# Проверка, играл ли сегодня

def played_today(user_id, chat_id):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT last_played FROM players WHERE user_id=? AND chat_id=?", (user_id, chat_id))
    row = cursor.fetchone()
    conn.close()
    if not row or not row[0]:
        return False
    last = datetime.date.fromisoformat(row[0])
    return last == datetime.datetime.now(ZoneInfo("Europe/Moscow")).date()

# Генерация и подсчёт номера

def generate_plate():
    letters = "АВЕКМНОРСТУХ"
    plate = random.choice(letters)
    plate += f"{random.randint(0, 999):03d}"
    plate += random.choice(letters) + random.choice(letters)
    return plate

def calculate_plate(plate):
    """
    1) Категория 3 — специальные номера из plates_config.py
    2) Категория 2 — 8 стандартных фич по таблице
    3) Категория 1 — обычный номер
    """
    # 1. Извлекаем цифры и буквы
    digits = plate[1:4]           # например "122"
    nums = [int(d) for d in digits]

    # --- КАТЕГОРИЯ 3: точное совпадение example в plates_config ---
    for combo in license_plates:
        if combo["example"] == plate:
            return combo["points_total"], combo["phrase"]

    # --- КАТЕГОРИЯ 2: 8 проверок в порядке приоритета ---

    # 1) Две соседние цифры одинаковые (пример A122BC)
    if nums[0] == nums[1] or nums[1] == nums[2]:
        return 20, f"{digits} — две одинаковые цифры рядом."

    # 2) Две зеркальные цифры (палиндром вокруг центра, B181HE)
    if digits[0] == digits[2] and digits[0] != digits[1]:
        return 50, f"{digits} — зеркальный набор цифр."

    # 3) Две зеркальные буквы (М345ВМ)
    if plate[0] == plate[4] and plate[0] != plate[5]:
        return 50, f"{plate[0]}…{plate[4]} — зеркальные буквы."

    # 4) Три одинаковые цифры (C333CT)
    if nums[0] == nums[1] == nums[2]:
        return 100, f"{digits} — три одинаковые цифры!"

    # 5) Три одинаковые буквы (A761AA)
    if plate[4] == plate[5] == plate[0]:
        return 100, f"{plate[4]} — три одинаковые буквы!"

    # 6) Арифметическая прогрессия цифр (K246KT)
    if (nums[1] - nums[0]) == (nums[2] - nums[1]) and abs(nums[1] - nums[0]) > 0:
        return 30, f"{digits} — цифры в арифметической прогрессии."

    # 7) Все чётные или все нечётные цифры (P864PR)
    if all(n % 2 == 0 for n in nums) or all(n % 2 == 1 for n in nums):
        return 25, f"{digits} — все цифры одной чётности."

    # 8) Последовательность 123 или 321 (E123EB)
    if (nums[1] - nums[0] == 1 and nums[2] - nums[1] == 1) \
        or (nums[0] - nums[1] == 1 and nums[1] - nums[2] == 1):
            return 35, f"{digits} — цифры идут подряд."

    # --- КАТЕГОРИЯ 1: обычный номер без фич ---
    return 15, "Обычный номерок, без понтов."

# --- Хендлеры ---
def _is_public_https(url: str) -> bool:
    # Telegram WebApp buttons require a valid public HTTPS URL.
    if not url.startswith("https://"):
        return False
    host = url.split("://", 1)[1].split("/", 1)[0]
    return not (host.startswith(("10.", "127.", "192.168.", "172.")) or "localhost" in host)


def _app_keyboard() -> InlineKeyboardMarkup | None:
    rows = []
    if _is_public_https(MINI_APP_URL):
        rows.append([InlineKeyboardButton("📱 Mini App", web_app=WebAppInfo(url=MINI_APP_URL))])
    if _is_public_https(MAX_APP_URL):
        rows.append([InlineKeyboardButton("MAX", url=MAX_APP_URL)])
    return InlineKeyboardMarkup(rows) if rows else None


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    chat_id = update.effective_chat.id
    save_player(user.id, user.username, chat_id)
    text = (
        "🚓 Добрый день, предъявите документы!\n"
        "📄 Жми /number, чтобы получить номерной знак.\n"
        "ℹ️ Или введи /help, чтобы посмотреть все команды."
    )
    try:
        await update.message.reply_text(text, reply_markup=_app_keyboard())
    except Exception:
        # Never let an invalid inline button (e.g. non-HTTPS WebApp URL) swallow /start.
        await update.message.reply_text(text)

async def number(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    chat_id = update.effective_chat.id
    save_player(user.id, user.username, chat_id)

    # Раз в день
    if update.effective_chat.type != 'private' and played_today(user.id, chat_id):
        await update.message.reply_text("🕒 Один раз в день — попробуй завтра.")
        return

    plate = generate_plate()
    points, phrase = calculate_plate(plate)

    # Сохраняем "черновик" до выбора
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute(
        """
        UPDATE players SET current_plate=?, current_points=?, has_exchanged=0
        WHERE user_id=? AND chat_id=?
        """,
        (plate, points, user.id, chat_id)
    )
    conn.commit()
    conn.close()

    keyboard = [[
        InlineKeyboardButton("✅ Принять", callback_data="accept"),
        InlineKeyboardButton("🔄 Обменять", callback_data="exchange")
    ]]
    await update.message.reply_text(
        f"🚘 Твой номер: {plate}\n💬 {phrase}\n🏅 Очки: {points}\n Регистрируем?",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def accept(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    # Оборачиваем answer() чтобы игнорировать сетевые сбои
    try:
        await query.answer()
    except NetworkError:
        pass

    user = query.from_user
    # Берём чат из message, а не из update.effective_chat
    chat = query.message.chat
    chat_id = chat.id

    # Ограничение 1 раз в день — только в группах
    if chat.type != 'private' and played_today(user.id, chat_id):
        await query.edit_message_text("🕒 Уже играл сегодня.")
        return

    # Получаем черновик
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT current_plate, current_points, total_points, best_points FROM players WHERE user_id=? AND chat_id=?",
        (user.id, chat_id)
    )
    row = cursor.fetchone() or (None, 0, 0, 0)
    plate, pts, total, best = row

    # Обновляем даты и очки
    new_total = total + pts
    now_date = datetime.datetime.now(ZoneInfo("Europe/Moscow")).date().isoformat()

    if pts > best:
        cursor.execute(
            """
            UPDATE players
            SET total_points=?, last_played=?, best_points=?, best_plate=?, current_plate=?, current_points=?
            WHERE user_id=? AND chat_id=?
            """,
            (new_total, now_date, pts, plate, plate, pts, user.id, chat_id)
        )
    else:
        cursor.execute(
            """
            UPDATE players
            SET total_points=?, last_played=?, current_plate=?, current_points=?
            WHERE user_id=? AND chat_id=?
            """,
            (new_total, now_date, plate, pts, user.id, chat_id)
        )
    conn.commit()
    conn.close()

    await query.edit_message_text(
        f"✅ Принято!\n🚘 Номер: {plate}\n🏅 Получено: {pts} очков\n💰 Итоговый баланс: {new_total}"
    )

async def exchange(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    # Защищаем колбэк от сетевых ошибок
    try:
        await query.answer()
    except NetworkError:
        pass

    user = query.from_user
    # Правильно берём чат
    chat = query.message.chat
    chat_id = chat.id

    # Ограничение 1 раз в день — только в группах
    if chat.type != 'private' and played_today(user.id, chat_id):
        await query.edit_message_text("🕒 Уже играл сегодня.")
        return

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT total_points FROM players WHERE user_id=? AND chat_id=?",
        (user.id, chat_id)
    )
    total = cursor.fetchone()[0]

    now_date = datetime.datetime.now(ZoneInfo("Europe/Moscow")).date().isoformat()
    base_cost = 5  # стоимость обмена

    if random.choice([True, False]):
        # Успешный обмен
        plate = generate_plate()
        pts, phr = calculate_plate(plate)
        new_total = total - base_cost + pts

        # Получаем предыдущий рекорд
        cursor.execute(
            "SELECT best_points FROM players WHERE user_id=? AND chat_id=?",
            (user.id, chat_id)
        )
        best_points = cursor.fetchone()[0]

        if pts > best_points:
            cursor.execute("""
                UPDATE players
                SET total_points=?, last_played=?, best_points=?, best_plate=?, current_plate=?, current_points=?
                WHERE user_id=? AND chat_id=?
            """, (new_total, now_date, pts, plate, plate, pts, user.id, chat_id))
        else:
            cursor.execute("""
                UPDATE players
                SET total_points=?, last_played=?, current_plate=?, current_points=?
                WHERE user_id=? AND chat_id=?
            """, (new_total, now_date, plate, pts, user.id, chat_id))

        conn.commit()
        conn.close()

        await query.edit_message_text(
            f"🔄 Обмен успешен!\n"
            f"🚘 Новый номер: {plate}\n"
            f"💬 {phr}\n"
            f"🏅 Получено: {pts} очков\n"
            f"💰 Итоговый баланс: {new_total}"
        )
    else:
        # Неудачная взятка — штраф 50 очков
        new_total = total - 50
        cursor.execute(
            "UPDATE players SET total_points=?, last_played=? WHERE user_id=? AND chat_id=?",
            (new_total, now_date, user.id, chat_id)
        )
        conn.commit()
        conn.close()

        await query.edit_message_text(
            f"👮‍♂️ Попался на взятке! Штраф -50 очков\n"
            f"💰 Итоговый баланс: {new_total}"
        )

async def restart(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat
    user = update.effective_user

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # 1) В личном чате любой сбросит только свои данные
    if chat.type == 'private':
        cursor.execute(
            "DELETE FROM players WHERE user_id = ? AND chat_id = ?",
            (user.id, chat.id)
        )
        conn.commit()
        conn.close()
        await update.message.reply_text("🔄 Ваши личные данные сброшены.")
        return

    # 2) В группе:
    # 2.1) Если вы – владелец бота (OWNER_ID), сбрасываем все данные группы
    if user.id == OWNER_ID:
        cursor.execute("DELETE FROM players WHERE chat_id = ?", (chat.id,))
        conn.commit()
        conn.close()
        await update.message.reply_text("🔄 Все данные этой группы сброшены")
        return

    # 2.2) Иначе только админ группы может сбросить всех
    try:
        member = await context.bot.get_chat_member(chat.id, user.id)
        if member.status not in ("creator", "administrator"):
            await update.message.reply_text("⛔ Нет доступа")
            conn.close()
            return
    except:
        await update.message.reply_text("⚠️ Не удалось проверить ваши права администратора.")
        conn.close()
        return

    # если мы дошли до сюда — админ группы:
    cursor.execute("DELETE FROM players WHERE chat_id = ?", (chat.id,))
    conn.commit()
    conn.close()
    await update.message.reply_text("🔄 Все данные этой группы сброшены.")

async def top(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT username, current_plate, total_points
        FROM players WHERE chat_id=? ORDER BY total_points DESC LIMIT 10
    """, (chat_id,))
    rows = cursor.fetchall()
    conn.close()
    if not rows:
        await update.message.reply_text("🏁 Пока никто не получил номера.")
        return
    msg = "<b>🏆 Топ игроков:</b>\n"
    for i, (u, p, t) in enumerate(rows, 1):
        msg += f"{i}. {u or 'Безымянный'} — {p or '-'} — {t} очков\n"
    await update.message.reply_text(msg, parse_mode="HTML")

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "<b>📋 Команды Автобота:</b>\n"
        "/start — запустить бота\n"
        "/number — получить номерной знак\n"
        "/top — топ игроков в этом чате\n"
        "/restart — сбросить данные (лично или в группе для админа)\n"
        "/help — список команд",
        parse_mode="HTML"
    )

async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE):
    err = context.error
    if isinstance(err, Forbidden):
        # Игнорируем ошибку «bot was blocked by the user»
        logging.warning(f"Bot blocked or cannot send message: {err}")
        return
    # Для всех остальных ошибок выводим стек в лог
    logging.exception(f"Unexpected error: {err}")

def build_application():
    if not TOKEN:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is not configured")
    init_db()
    app = ApplicationBuilder().token(TOKEN).request(request).build()
    app.add_error_handler(error_handler)
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("number", number))
    app.add_handler(CommandHandler("top", top))
    app.add_handler(CommandHandler("restart", restart))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CallbackQueryHandler(accept, pattern="^accept$"))
    app.add_handler(CallbackQueryHandler(exchange, pattern="^exchange$"))
    return app


async def configure_commands(application) -> None:
    commands = [
        BotCommand("start", "Запустить бота"),
        BotCommand("number", "Получить номерной знак"),
        BotCommand("top", "Топ игроков чата"),
        BotCommand("restart", "Сбросить данные"),
        BotCommand("help", "Список команд бота"),
    ]
    await application.bot.set_my_commands(commands)


async def main():
    app = build_application()
    try:
        await configure_commands(app)
    except TimedOut:
        logging.warning("Не удалось установить меню команд: таймаут соединения.")
    print("🚔 Автобот готов к патрулю!")
    await app.run_polling()


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
