# --- Импорты ---
import os
import sqlite3
import random
import datetime
from zoneinfo import ZoneInfo
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand, WebAppInfo
from telegram.ext import (
    ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes, Defaults, MessageHandler, filters
)
from balloon_config import BALLOON_TYPES, ALL_COLORS_BONUS
from achievements_config import ACHIEVEMENTS, RANKS
import asyncio
import sys
import nest_asyncio

# Исправление конфликта цикла событий (Windows + Python 3.11+)
if sys.platform.startswith('win') and sys.version_info >= (3, 8):
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    nest_asyncio.apply()

# --- Настройки ---
TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
BOSS_ID = int(os.getenv("BOSS_ID", "484184861"))
DB_FILE = os.getenv("DB_FILE", "balloon_game.db")
MINI_APP_URL = os.getenv("TELEGRAM_MINI_APP_URL", "").strip()
MAX_APP_URL = os.getenv("MAX_APP_URL", "").strip()
user_data = {}

# --- Инициализация БД ---
def init_db():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("""
    CREATE TABLE IF NOT EXISTS scores (
        user_id INTEGER,
        username TEXT,
        chat_id INTEGER,
        points INTEGER DEFAULT 0,
        last_play TEXT,
        games_played INTEGER DEFAULT 0,
        max_points INTEGER DEFAULT 0,
        total_points INTEGER DEFAULT 0,
        triplets INTEGER DEFAULT 0,
        nions INTEGER DEFAULT 0,
            PRIMARY KEY (user_id, chat_id)
    )""")
    conn.commit()
    conn.close()

    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("PRAGMA table_info(scores)")
    columns = [column[1] for column in c.fetchall()]
    if "achievement_points" not in columns:
        c.execute("ALTER TABLE scores ADD COLUMN achievement_points INTEGER DEFAULT 0;")
    c.execute("""
    CREATE TABLE IF NOT EXISTS user_achievements (
        user_id INTEGER,
        chat_id INTEGER,
        achievement_id TEXT,
        PRIMARY KEY (user_id, chat_id, achievement_id)
    )
    """)
    conn.commit()
    conn.close()

# --- Сохранение пользователя ---
def save_user(user_id, username):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT OR REPLACE INTO scores (user_id, username, chat_id) VALUES (?, ?, ?)", 
              (user_id, username or "Unknown", 0))
    conn.commit()
    conn.close()

# --- Обновление очков (Исправленная функция полностью!) ---
def update_scores(user_id, username, chat_id, points, triplets, nions, sphere_counts, triplet_counts, nions_counts):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    c.execute("""
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
            blue_spheres = blue_spheres + ?, red_spheres = red_spheres + ?, green_spheres = green_spheres + ?, gold_spheres = gold_spheres + ?, purple_spheres = purple_spheres + ?,
            blue_triplets = blue_triplets + ?, red_triplets = red_triplets + ?, green_triplets = green_triplets + ?, purple_triplets = purple_triplets + ?, green_nions = green_nions + ?
    """, (
        user_id, username, chat_id, points,
        datetime.datetime.now(ZoneInfo("Europe/Moscow")).isoformat(),
        points, points, triplets, nions,
        sphere_counts["blue"], sphere_counts["red"], sphere_counts["green"], sphere_counts["gold"], sphere_counts["purple"],
        triplet_counts["blue"], triplet_counts["red"], triplet_counts["green"], triplet_counts["purple"], nions_counts["green"],
        points, username, datetime.datetime.now(ZoneInfo("Europe/Moscow")).isoformat(),
        points, points, triplets, nions,
        sphere_counts["blue"], sphere_counts["red"], sphere_counts["green"], sphere_counts["gold"], sphere_counts["purple"],
        triplet_counts["blue"], triplet_counts["red"], triplet_counts["green"], triplet_counts["purple"], nions_counts["green"]
    ))
    conn.commit()
    conn.close()

# --- Проверка игры сегодня ---
def already_played_today(user_id, chat_id):
    now = datetime.datetime.now(ZoneInfo("Europe/Moscow"))
    today = now.date()
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT last_play FROM scores WHERE user_id = ? AND chat_id = ?", (user_id, chat_id))
    row = c.fetchone()
    conn.close()
    if not row or not row[0]:
        return False
    last_play_dt = datetime.datetime.fromisoformat(row[0])
    return last_play_dt.date() == today

# --- Проверка и выдача достижений ---
async def check_achievements(user_id, chat_id, game_collection):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    # Получаем текущие данные пользователя
    c.execute("""
        SELECT games_played, max_points, total_points, triplets, nions, achievement_points 
        FROM scores WHERE user_id=? AND chat_id=?""",
        (user_id, chat_id)
    )
    user_data = c.fetchone()

    if not user_data:
        conn.close()
        return []

    (games_played, max_points, total_points, triplets, nions, current_achievement_points) = user_data
    new_achievements = []

    # Подсчёт использованных цветов
    colors_used_in_game = set()
    if game_collection.get("blue_spheres") or game_collection.get("blue_triplets"):
        colors_used_in_game.add("blue")
    if game_collection.get("red_spheres") or game_collection.get("red_triplets"):
        colors_used_in_game.add("red")
    if game_collection.get("green_spheres") or game_collection.get("green_triplets") or game_collection.get("green_nions"):
        colors_used_in_game.add("green")
    if game_collection.get("gold_spheres"):
        colors_used_in_game.add("gold")
    if game_collection.get("purple_spheres") or game_collection.get("purple_triplets"):
        colors_used_in_game.add("purple")

# --- Правильная проверка достижений по цветам ---
    for ach in ACHIEVEMENTS:
        c.execute("""
            SELECT 1 FROM user_achievements WHERE user_id=? AND chat_id=? AND achievement_id=?""",
            (user_id, chat_id, ach["id"])
        )
        if c.fetchone():
            continue

        condition_met = False
        condition = ach["condition"]

        # Проверка базовых условий
        if "games_played" in condition and games_played >= condition["games_played"]:
            condition_met = True
        elif "max_game_points" in condition and max_points >= condition["max_game_points"]:
            condition_met = True
        elif "total_game_points" in condition and total_points >= condition["total_game_points"]:
            condition_met = True
        elif "total_triplets" in condition and triplets >= condition["total_triplets"]:
            condition_met = True
        elif "total_nions" in condition and nions >= condition["total_nions"]:
            condition_met = True

        # Достижение "5 цветов" (только все 5 цветов одновременно)
        elif (
            "blue_spheres_or_triplets" in condition and
            "red_spheres_or_triplets" in condition and
            "green_spheres_or_nions" in condition and
            "gold_spheres" in condition and
            "purple_spheres_or_triplets" in condition and
            len(colors_used_in_game) == 5
        ):
            condition_met = True

        # Достижения за "ТОЛЬКО N цветов"
        elif (
            ("EXACTLY_4_COLORS" in condition and len(colors_used_in_game) == 4) or
            ("EXACTLY_3_COLORS" in condition and len(colors_used_in_game) == 3) or
            ("EXACTLY_2_COLORS" in condition and len(colors_used_in_game) == 2) or
            ("EXACTLY_1_COLOR" in condition and len(colors_used_in_game) == 1)
        ):
            condition_met = True

        if condition_met:
            c.execute("""
                INSERT INTO user_achievements (user_id, chat_id, achievement_id)
                VALUES (?, ?, ?)""",
                (user_id, chat_id, ach["id"])
            )
            c.execute("""
                UPDATE scores SET achievement_points = achievement_points + ?
                WHERE user_id=? AND chat_id=?""",
                (ach["achievement_points"], user_id, chat_id)
            )
            new_achievements.append(ach["name"])

    conn.commit()
    conn.close()

    # Возвращаем список новых достижений
    return new_achievements

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
    if not rows:
        return None
    return InlineKeyboardMarkup(rows)


# --- /start ---
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    save_user(user.id, user.username)
    text = (
        f"Добро пожаловать, {user.first_name}! Это Мастер сфер.\n"
        f"Используй /ball, чтобы начать, или /help чтобы увидеть список команд."
    )
    markup = _app_keyboard()
    try:
        await update.message.reply_text(text, reply_markup=markup)
    except Exception:
        # Never let an invalid inline button (e.g. non-HTTPS WebApp URL) swallow /start.
        await update.message.reply_text(text)

# --- /help ---
async def help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    help_text = "📜 <b>Список команд бота:</b>\n\n"
    help_text += "/start — Начать работу с ботом\n"
    help_text += "/ball — Начать новую игру\n"
    help_text += "/stats — Твоя статистика\n"
    help_text += "/achievements — Достижения\n"
    help_text += "/how — Как играть\n"
    help_text += "/reset — Сбросить результаты (админ)\n"

    await update.message.reply_text(help_text, parse_mode='HTML')

# --- команда /how (отправляет картинку с пояснением бонусов) ---
async def how(update: Update, context: ContextTypes.DEFAULT_TYPE):
    file_id = "AgACAgIAAxkBAAIDbmgrcf9D_621osyFbtvIURa5j8ESAALY7zEbOhJgSdxOt1Ty8xagAQADAgADeAADNgQ"
    caption = "🔮 <b> Правила игры:</b>"
    await update.message.reply_photo(photo=file_id, caption=caption, parse_mode='HTML')

# --- команда /stats с достижениями ---
async def stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat.type != 'private' else user_id

    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("""
        SELECT games_played, max_points, total_points, triplets, nions, achievement_points
        FROM scores WHERE chat_id = ? AND user_id = ?
    """, (chat_id, user_id))
    data = c.fetchone()

    # Получаем список выполненных достижений игрока:
    c.execute("SELECT achievement_id FROM user_achievements WHERE user_id=? AND chat_id=?", (user_id, chat_id))
    user_achieved = [row[0] for row in c.fetchall()]

    conn.close()

    if data:
        games_played, max_points, total_points, triplets, nions, achievement_points = data

        # Определяем звание
        current_rank = next((rank["title"] for rank in RANKS if rank["min_achievement_points"] <= achievement_points <= rank["max_achievement_points"]), "Новичок")

        stats_text = (f"🎖 <b>Звание:</b> {current_rank}\n\n"
                      f"🎲 Сыграно партий: {games_played}\n"
                      f"🏅 Максимально очков: {max_points}\n"
                      f"💎 Всего очков: {total_points}\n"
                      f"🔮 Триплетов: {triplets}\n"
                      f"✨ Нионсов: {nions}\n\n"
                      f"🏆 Очки достижений: {achievement_points}\n"
                      f"📜 Выполненные достижения: {len(user_achieved)}/{len(ACHIEVEMENTS)}")
    else:
        stats_text = "🕹 Ты ещё не сыграл ни одной игры."

    await update.message.reply_text(stats_text, parse_mode='HTML')

# --- команда /achievements (список достижений игрока) ---
async def achievements(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat.type != 'private' else user_id

    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT achievement_id FROM user_achievements WHERE user_id=? AND chat_id=?", (user_id, chat_id))
    user_achieved = [row[0] for row in c.fetchall()]
    conn.close()

    achievements_text = "<b>🏅 Твои достижения:</b>\n\n"
    for ach in ACHIEVEMENTS:
        achieved_mark = "✅" if ach["id"] in user_achieved else "❌"
        achievements_text += (
            f"{achieved_mark} <b>{ach['name']}</b> "
            f"(+{ach['achievement_points']} очков) — {ach['description']}\n"
        )

    await update.message.reply_text(achievements_text, parse_mode='HTML')

# --- Команда /ball (начать игру) ---
async def ball(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    chat_id = update.effective_chat.id
    is_private = update.effective_chat.type == 'private'
    save_user(user.id, user.username)

    if not is_private and already_played_today(user.id, chat_id):
        await update.message.reply_text("🕒 Сегодня вы уже играли.")
        return

    colors = [config["emoji"] for config in BALLOON_TYPES.values()]  # исправлено
    initial_balls = [random.choice(colors) for _ in range(5)]
    user_data[user.id] = {
        "chat_id": chat_id,
        "private": is_private,
        "collection": initial_balls,
        "round": 1,
        "selected": []
    }

    offer_num, pick_num = calculate_offer_and_pick(initial_balls)
    current_offer = [random.choice(colors) for _ in range(offer_num)]
    user_data[user.id].update({
        "offer": current_offer,
        "pick_count": pick_num,
        "selected": []
    })

    keyboard_buttons = [InlineKeyboardButton(f"[{i+1}] {ball}", callback_data=f"toggle_{user.id}_{i}") 
                        for i, ball in enumerate(current_offer)]
    keyboard_layout = [keyboard_buttons[i:i+5] for i in range(0, len(keyboard_buttons), 5)]
    keyboard_layout.append([InlineKeyboardButton("✅ Принять", callback_data=f"accept_{user.id}")])

    now = datetime.datetime.now(ZoneInfo("Europe/Moscow")).isoformat()
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("""
        INSERT INTO scores (user_id, chat_id, last_play)
        VALUES (?, ?, ?)
        ON CONFLICT(user_id, chat_id) DO UPDATE SET last_play = ?
    """, (user.id, chat_id, now, now))
    conn.commit()
    conn.close()

    message_text = (
        f"<b>Раунд 1/5.</b>\n\n"
        f"{display_balloon_collection(initial_balls)}\n\n"
        f"Выберите <b>{pick_num}</b> из {offer_num}:"
    )

    await update.message.reply_text(
        message_text,
        reply_markup=InlineKeyboardMarkup(keyboard_layout),
        parse_mode='HTML'
    )

# --- Расчёт количества шаров на ход ---
def calculate_offer_and_pick(collection):
    # Подсчет общего количества синих и красных сфер
    blue_total = collection.count('🧿')
    red_total = collection.count('☄️')

    # Считаем количество триплетов отдельно (по 3 сферы = 1 триплет)
    blue_triplets = blue_total // 3
    red_triplets = red_total // 3

    # Бонусы теперь дают ТОЛЬКО триплеты, отдельные сферы бонусы НЕ ДАЮТ
    offer_num = 6 + blue_triplets
    pick_num = 3 + red_triplets

    return offer_num, pick_num

# --- Отображение собранных сфер между раундами с учетом желтых (исправлено) ---
def display_balloon_collection(collection):
    from collections import Counter

    emoji_to_color = {config["emoji"]: color for color, config in BALLOON_TYPES.items()}
    count = Counter(collection)
    details = []

    def get_correct_form(number, singular, few, many):
        if 11 <= number % 100 <= 14:
            return many
        if number % 10 == 1:
            return singular
        if 2 <= number % 10 <= 4:
            return few
        return many

    for emoji, color in emoji_to_color.items():
        total = count.get(emoji, 0)
        if total == 0:
            continue

        super_triplets = triplets = singles = 0

        if color == "green":
            super_triplets = total // 9
            total %= 9
            triplets = total // 3
            singles = total % 3
        elif color == "gold":  # четко прописано исключение для желтых
            singles = total  # Желтые всегда остаются одиночными!
        else:
            triplets = total // 3
            singles = total % 3

        sphere_parts = []
        if super_triplets:
            sphere_parts.append(f"{super_triplets} {get_correct_form(super_triplets, 'нионс', 'нионса', 'нионсов')}")
        if triplets:
            sphere_parts.append(f"{triplets} {get_correct_form(triplets, 'триплет', 'триплета', 'триплетов')}")
        if singles:
            sphere_parts.append(f"{singles} {get_correct_form(singles, 'сфера', 'сферы', 'сфер')}")

        details.append(f"{emoji} — собрано " + ", ".join(sphere_parts))

    return "Собранные сферы:\n" + "\n".join(details)

# --- Исправленный подсчёт итоговых очков ---
def calculate_score(collection):
    from collections import Counter
    total_points = 0
    details = []
    emoji_to_color = {config["emoji"]: color for color, config in BALLOON_TYPES.items()}
    count = Counter(collection)
    collected_colors = 0

    def get_correct_form(number, singular, few, many):
        if 11 <= number % 100 <= 14:
            return many
        if number % 10 == 1:
            return singular
        if 2 <= number % 10 <= 4:
            return few
        return many

    for emoji, color in emoji_to_color.items():
        config = BALLOON_TYPES[color]
        total = count.get(emoji, 0)

        if total == 0:
            continue

        collected_colors += 1
        super_triplets = triplets = singles = 0

        if color == "green":
            super_triplets = total // 9
            total %= 9
            triplets = total // 3
            singles = total % 3
        elif color == "gold":
            singles = total  # Желтые НЕ собираются в триплеты
        else:
            triplets = total // 3
            singles = total % 3

        if super_triplets and config.get("super_triplet_points"):
            score = super_triplets * config["super_triplet_points"]
            details.append(
                f"{emoji} — {super_triplets} {get_correct_form(super_triplets, 'нионс', 'нионса', 'нионсов')}: +{score} очков")
            total_points += score

        # Очки за триплеты
        if triplets:
            if "triplet_points_range" in config:
                triplet_points = sum(random.randint(*config["triplet_points_range"]) for _ in range(triplets))
            else:
                triplet_points = triplets * config["triplet_points"]
            details.append(f"{emoji} — {triplets} {get_correct_form(triplets, 'триплет', 'триплета', 'триплетов')}: +{triplet_points} очков")
            total_points += triplet_points

        # Очки за одиночные сферы
        if singles:
            if "single_points_range" in config:
                single_points = sum(random.randint(*config["single_points_range"]) for _ in range(singles))
            else:
                single_points = singles * config["single_points"]
            details.append(f"{emoji} — {singles} {get_correct_form(singles, 'сфера', 'сферы', 'сфер')}: +{single_points} очков")
            total_points += single_points

    if collected_colors == len(BALLOON_TYPES):
        details.append(f"\n💎 Бонус за все цвета: +{ALL_COLORS_BONUS} очков")
        total_points += ALL_COLORS_BONUS

    details.append(f"<b>\n🎖️ Итого очков: {total_points}</b>")
    return "\n".join(details), total_points

# --- Команда /reset (сброс очков и достижений, в группах — только админ, в личке — любой пользователь) ---
async def reset(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    chat = update.effective_chat
    user_id = user.id
    save_user(user_id, user.username)

    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    if chat.type == "private":
        # Сброс данных текущего пользователя в личке
        c.execute("DELETE FROM scores WHERE chat_id = ?", (chat.id,))
        c.execute("DELETE FROM user_achievements WHERE chat_id = ?", (chat.id,))
        conn.commit()
        conn.close()
        await update.message.reply_text("🔄 Ваши очки и достижения успешно сброшены.")
        return

    # Для групп: только BOSS_ID
    if user_id != BOSS_ID:
        await update.message.reply_text("⛔ У вас нет прав на сброс результатов в группе.")
        conn.close()
        return

    # Сброс всех данных группы (очки и достижения)
    c.execute("DELETE FROM scores WHERE chat_id = ?", (chat.id,))
    c.execute("DELETE FROM user_achievements WHERE chat_id = ?", (chat.id,))
    conn.commit()
    conn.close()

    # Очистка текущих игровых данных в памяти
    for uid, data in list(user_data.items()):
        if data.get("chat_id") == chat.id:
            user_data.pop(uid, None)

    await update.message.reply_text("🔄 Очки и достижения всех игроков в этом чате сброшены!")

# --- Обработка кнопок ---
async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    data = query.data
    user_click = query.from_user
    user_id = user_click.id

    if data.startswith("toggle_"):
        _, game_user_id_str, index_str = data.split("_")
        game_user_id, index = int(game_user_id_str), int(index_str)
        if user_id != game_user_id:
            await query.answer("Это не ваша игра!", show_alert=True)
            return
        game = user_data.get(game_user_id)
        if not game:
            await query.answer("Игра не найдена.")
            return
        selected = game["selected"]
        if index in selected:
            selected.remove(index)
        else:
            if len(selected) >= game["pick_count"]:
                await query.answer(f"Максимум {game['pick_count']} сфер!", show_alert=True)
                return
            selected.append(index)
        game["selected"] = selected
        buttons = [InlineKeyboardButton(
            ("✅ " if i in selected else f"[{i+1}] ") + ball, 
            callback_data=f"toggle_{game_user_id}_{i}"
        ) for i, ball in enumerate(game["offer"])]
        layout = [buttons[i:i+5] for i in range(0, len(buttons), 5)]
        layout.append([InlineKeyboardButton("✅ Принять", callback_data=f"accept_{game_user_id}")])
        await query.edit_message_reply_markup(InlineKeyboardMarkup(layout))

    elif data.startswith("accept_"):
        _, game_user_id_str = data.split("_")
        game_user_id = int(game_user_id_str)
        if user_id != game_user_id:
            await query.answer("Это не ваша игра!", show_alert=True)
            return

        game = user_data.get(game_user_id)
        if not game or len(game["selected"]) != game["pick_count"]:
            await query.answer("Выберите нужное количество сфер!", show_alert=True)
            return

        chosen = [game["offer"][i] for i in game["selected"]]
        game["collection"].extend(chosen)

        if game["round"] < 5:
            game["round"] += 1
            colors = [config["emoji"] for config in BALLOON_TYPES.values()]
            offer_num, pick_num = calculate_offer_and_pick(game["collection"])
            new_offer = [random.choice(colors) for _ in range(offer_num)]
            game.update({"offer": new_offer, "pick_count": pick_num, "selected": []})
            buttons = [InlineKeyboardButton(f"[{i+1}] {ball}", callback_data=f"toggle_{game_user_id}_{i}")
                    for i, ball in enumerate(new_offer)]
            layout = [buttons[i:i+5] for i in range(0, len(buttons), 5)]
            layout.append([InlineKeyboardButton("✅ Принять", callback_data=f"accept_{game_user_id}")])
            msg = (
                f"<b>Раунд {game['round']}/5.</b>\n\n"
                f"{display_balloon_collection(game['collection'])}\n\n"
                f"Выберите <b>{pick_num}</b> из {offer_num}:"
            )

            await query.edit_message_text(
                msg,
                reply_markup=InlineKeyboardMarkup(layout),
                parse_mode='HTML'
            )

        else:
            details_text, total_points = calculate_score(game["collection"])

            triplets_count = 0
            nions_count = 0
            from collections import Counter
            counts = Counter(game["collection"])

            # Правильно собираем данные по всем сферам
            sphere_counts = {color: 0 for color in BALLOON_TYPES}
            triplet_counts = {color: 0 for color in BALLOON_TYPES}
            nions_counts = {color: 0 for color in BALLOON_TYPES}

            for color, config in BALLOON_TYPES.items():
                emoji = config["emoji"]
                total = counts.get(emoji, 0)

                if color == "green":
                    nions_counts[color] = total // 9
                    total %= 9
                    triplet_counts[color] = total // 3
                    sphere_counts[color] = total % 3
                    nions_count += nions_counts[color]
                    triplets_count += triplet_counts[color]
                elif color == "gold":
                    sphere_counts[color] = total
                else:
                    triplet_counts[color] = total // 3
                    sphere_counts[color] = total % 3
                    triplets_count += triplet_counts[color]

            chat_id = game["chat_id"] if not game["private"] else user_id

            # Исправлено: правильный вызов с точными параметрами
            update_scores(
                user_id, user_click.username, chat_id, total_points, triplets_count, nions_count,
                sphere_counts, triplet_counts, nions_counts
            )

            await query.edit_message_text(
                f"<b>🎉 Игра окончена!</b>\n\n{details_text}",
                parse_mode='HTML'
            )

            game_collection_counts = {
                "blue_spheres": sphere_counts["blue"],
                "red_spheres": sphere_counts["red"],
                "green_spheres": sphere_counts["green"],
                "gold_spheres": sphere_counts["gold"],
                "purple_spheres": sphere_counts["purple"],
                "blue_triplets": triplet_counts["blue"],
                "red_triplets": triplet_counts["red"],
                "green_triplets": triplet_counts["green"],
                "purple_triplets": triplet_counts["purple"],
                "green_nions": nions_counts["green"]
            }

            # Проверяем и выдаём достижения (исправлено)
            new_achievements = await check_achievements(user_id, chat_id, game_collection_counts)
            if new_achievements:
                achievements_msg = "✨ <b>Новые достижения:</b>\n- " + "\n- ".join(new_achievements)
                await query.message.reply_text(achievements_msg, parse_mode='HTML')

# --- Функция получения file_id картинки ---
async def get_photo_id(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.message.photo:
        file_id = update.message.photo[-1].file_id
        await update.message.reply_text(f"📸 File ID картинки:\n\n<code>{file_id}</code>", parse_mode='HTML')

def build_application():
    if not TOKEN:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is not configured")
    init_db()
    app = ApplicationBuilder().token(TOKEN).defaults(Defaults(parse_mode='HTML')).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help))
    app.add_handler(CommandHandler("ball", ball))
    app.add_handler(CommandHandler("stats", stats))
    app.add_handler(CommandHandler("reset", reset))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.PHOTO, get_photo_id))
    app.add_handler(CommandHandler("how", how))
    app.add_handler(CommandHandler("achievements", achievements))
    return app


async def configure_commands(application) -> None:
    commands = [
        BotCommand("start", "Начать работу с ботом"),
        BotCommand("help", "Список команд бота"),
        BotCommand("ball", "Начать новую игру"),
        BotCommand("stats", "Твоя статистика"),
        BotCommand("achievements", "Показать достижения"),
        BotCommand("how", "Как играть"),
        BotCommand("reset", "Сбросить результаты (админ)"),
    ]
    await application.bot.set_my_commands(commands)


async def main():
    app = build_application()
    await configure_commands(app)
    print("Сферы созданы")
    await app.run_polling()


if __name__ == "__main__":
    asyncio.run(main())