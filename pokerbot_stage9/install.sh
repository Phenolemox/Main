#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="Phenolemox/poker-bot"
TARGET_DIR="/opt/repos/poker-bot"

if [ ! -d "$TARGET_DIR/.git" ]; then
  rm -rf "$TARGET_DIR"
  gh repo clone "$TARGET_REPO" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
git remote set-url origin "https://github.com/${TARGET_REPO}.git" 2>/dev/null || true
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

python3 - <<'PY'
from pathlib import Path

root = Path('/opt/repos/poker-bot')
files = {
'app/bot/rate_limit.py': r'''
from __future__ import annotations

import asyncio
import time


class MemoryThrottle:
    def __init__(self) -> None:
        self._last: dict[str, float] = {}
        self._lock = asyncio.Lock()

    async def allow(self, key: str, interval_seconds: float) -> bool:
        now = time.monotonic()
        async with self._lock:
            last = self._last.get(key, 0.0)
            if now - last < interval_seconds:
                return False
            self._last[key] = now
            if len(self._last) > 20000:
                cutoff = now - 300
                self._last = {k: v for k, v in self._last.items() if v >= cutoff}
            return True


throttle = MemoryThrottle()
'''.strip() + '\n',

'app/bot/duels.py': r'''
from __future__ import annotations

import time
from dataclasses import dataclass
from secrets import token_urlsafe


@dataclass
class PendingDuel:
    duel_id: str
    chat_id: str
    chat_db_id: int
    challenger_user_id: int
    opponent_user_id: int
    challenger_name: str
    opponent_name: str
    created_at: float
    expires_at: float


class DuelManager:
    def __init__(self) -> None:
        self._duels: dict[str, PendingDuel] = {}

    def _cleanup(self) -> None:
        now = time.time()
        expired = [k for k, duel in self._duels.items() if duel.expires_at <= now]
        for key in expired:
            self._duels.pop(key, None)

    def create(
        self,
        *,
        chat_id: str,
        chat_db_id: int,
        challenger_user_id: int,
        opponent_user_id: int,
        challenger_name: str,
        opponent_name: str,
        ttl_seconds: int = 60,
    ) -> tuple[PendingDuel | None, str | None]:
        self._cleanup()
        now = time.time()
        for duel in self._duels.values():
            if duel.chat_id != chat_id:
                continue
            busy = {duel.challenger_user_id, duel.opponent_user_id}
            if challenger_user_id in busy or opponent_user_id in busy:
                return None, 'У одного из игроков уже висит вызов. Дождись ответа или истечения таймера.'
        duel_id = token_urlsafe(8)
        duel = PendingDuel(
            duel_id=duel_id,
            chat_id=chat_id,
            chat_db_id=chat_db_id,
            challenger_user_id=challenger_user_id,
            opponent_user_id=opponent_user_id,
            challenger_name=challenger_name,
            opponent_name=opponent_name,
            created_at=now,
            expires_at=now + ttl_seconds,
        )
        self._duels[duel_id] = duel
        return duel, None

    def get(self, duel_id: str) -> PendingDuel | None:
        self._cleanup()
        return self._duels.get(duel_id)

    def pop(self, duel_id: str) -> PendingDuel | None:
        self._cleanup()
        return self._duels.pop(duel_id, None)


duel_manager = DuelManager()
'''.strip() + '\n',

'app/bot/common.py': r'''
def normalize_command(text: str) -> tuple[str, str]:
    raw = (text or '').strip()
    if not raw.startswith('/'):
        return '', raw
    first, *rest = raw.split(maxsplit=1)
    cmd = first.split('@', 1)[0].lower()
    args = rest[0].strip() if rest else ''
    return cmd, args


def format_user_name(username: str | None, display_name: str | None, fallback: str) -> str:
    if display_name:
        return display_name
    if username:
        return '@' + username
    return fallback


def public_player_name(item: dict) -> str:
    return item.get('display_name') or ('Игрок ' + str(item.get('user_id')))


def format_leaderboard(items: list[dict], title: str) -> str:
    if not items:
        return 'Пока никто не играл.'
    medals = ['🥇', '🥈', '🥉']
    lines = [title]
    for idx, item in enumerate(items, start=1):
        prefix = medals[idx - 1] if idx <= 3 else f'{idx}.'
        name = public_player_name(item)
        lines.append(f"{prefix} {name} — {item.get('score', 0)} очков")
    return '\n'.join(lines)
'''.strip() + '\n',

'app/bot/telegram.py': r'''
from __future__ import annotations

import re

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bot.common import format_leaderboard, format_user_name, normalize_command
from app.bot.duels import duel_manager
from app.bot.rate_limit import throttle
from app.core.config import get_settings
from app.db.models import ScoreLedger, User
from app.db.repositories import add_score, get_or_create_chat, get_or_create_user, leaderboard
from app.game.cards import PHRASES, best_of_seven, deal_classic, deal_holdem_duel, evaluate_five, format_cards
from app.game.scoring import score_duel

HELP_TEXT = """📋 Команды:
/start — главное меню
/cards — быстрая раздача
/topscore — рейтинг
/topduel — дуэли
/profile — профиль
/nick Имя — сменить игровой ник
/duel @ник — дуэль в группе"""

START_TEXT = "🎰 Добро пожаловать за стол. Сделай ход."
DUEL_HINT_PRIVATE = "⚔️ Дуэли работают в группах. Добавь бота в чат и вызови игрока: /duel @ник"
DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. У вызванного игрока будет 60 секунд принять или отказаться."
NICK_HINT = "✍️ Ник для рейтингов:\n/nick ТвойНик"
NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')


def main_keyboard(chat_type: str = 'private') -> dict:
    rows = [
        [
            {'text': '🃏 Раздача', 'callback_data': 'cards'},
            {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'},
        ],
        [
            {'text': '🏆 Топ', 'callback_data': 'topscore'},
            {'text': '👤 Профиль', 'callback_data': 'profile'},
        ],
        [{'text': '📋 Помощь', 'callback_data': 'help'}],
    ]
    if chat_type != 'private':
        rows[1] = [
            {'text': '🏆 Топ игры', 'callback_data': 'topscore'},
            {'text': '⚔️ Топ дуэлей', 'callback_data': 'topduel'},
        ]
        rows[2] = [
            {'text': '👤 Профиль', 'callback_data': 'profile'},
            {'text': '📋 Помощь', 'callback_data': 'help'},
        ]
    return {'inline_keyboard': rows}


def cards_keyboard(chat_type: str = 'private') -> dict:
    return {
        'inline_keyboard': [
            [
                {'text': '🃏 Ещё', 'callback_data': 'cards'},
                {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'},
            ],
            [
                {'text': '🏆 Топ', 'callback_data': 'topscore'},
                {'text': '⬅️ Меню', 'callback_data': 'menu'},
            ],
        ]
    }


def top_keyboard(chat_type: str = 'private') -> dict:
    return {
        'inline_keyboard': [
            [
                {'text': '🃏 Раздача', 'callback_data': 'cards'},
                {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'},
            ],
            [
                {'text': '👤 Профиль', 'callback_data': 'profile'},
                {'text': '⬅️ Меню', 'callback_data': 'menu'},
            ],
        ]
    }


def profile_keyboard(chat_type: str = 'private') -> dict:
    return {
        'inline_keyboard': [
            [
                {'text': '🃏 Раздача', 'callback_data': 'cards'},
                {'text': '🏆 Топ', 'callback_data': 'topscore'},
            ],
            [
                {'text': '✍️ Ник', 'callback_data': 'nick_help'},
                {'text': '⬅️ Меню', 'callback_data': 'menu'},
            ],
        ]
    }


def duel_keyboard(chat_type: str = 'private') -> dict:
    return {
        'inline_keyboard': [
            [
                {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'},
                {'text': '⚔️ Топ дуэлей', 'callback_data': 'topduel'},
            ],
            [
                {'text': '🃏 Раздача', 'callback_data': 'cards'},
                {'text': '⬅️ Меню', 'callback_data': 'menu'},
            ],
        ]
    }


def duel_request_keyboard(duel_id: str) -> dict:
    return {
        'inline_keyboard': [
            [
                {'text': '✅ Принять', 'callback_data': f'duel_accept:{duel_id}'},
                {'text': '❌ Отказаться', 'callback_data': f'duel_decline:{duel_id}'},
            ]
        ]
    }


def _chat_type(update_message: dict) -> str:
    return (update_message.get('chat') or {}).get('type') or 'private'


def _chat_id(update_message: dict) -> str:
    return str((update_message.get('chat') or {}).get('id') or '')


def _chat_title(update_message: dict) -> str | None:
    chat = update_message.get('chat') or {}
    return chat.get('title') or chat.get('first_name') or chat.get('username')


def _from_profile(update_message: dict) -> dict:
    src = update_message.get('from') or {}
    first = src.get('first_name') or ''
    last = src.get('last_name') or ''
    display = (first + ' ' + last).strip() or src.get('username') or str(src.get('id') or 'unknown')
    return {
        'platform_user_id': str(src.get('id') or 'unknown'),
        'username': src.get('username'),
        'display_name': display,
        'raw_profile': src,
    }


async def send_telegram_message(chat_id: str | int, text: str, *, parse_mode: str | None = None, reply_markup: dict | None = None) -> dict:
    settings = get_settings()
    token = settings.telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'chat_id': str(chat_id), 'text': text, 'reply_markup': reply_markup}
    payload = {'chat_id': chat_id, 'text': text, 'disable_web_page_preview': True}
    if parse_mode:
        payload['parse_mode'] = parse_mode
    if reply_markup:
        payload['reply_markup'] = reply_markup
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f'https://api.telegram.org/bot{token}/sendMessage', json=payload)
    return {'status_code': response.status_code, 'ok': response.is_success}


async def answer_callback_query(callback_query_id: str, text: str = 'Принято') -> dict:
    settings = get_settings()
    token = settings.telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'callback_query_id': callback_query_id, 'text': text}
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            f'https://api.telegram.org/bot{token}/answerCallbackQuery',
            json={'callback_query_id': callback_query_id, 'text': text, 'show_alert': False},
        )
    return {'status_code': response.status_code, 'ok': response.is_success}


async def _profile_text(db: AsyncSession, user: User) -> str:
    global_score = await db.scalar(select(func.coalesce(func.sum(ScoreLedger.delta), 0)).where(ScoreLedger.user_id == user.id, ScoreLedger.scope == 'global'))
    duel_score = await db.scalar(select(func.coalesce(func.sum(ScoreLedger.delta), 0)).where(ScoreLedger.user_id == user.id, ScoreLedger.scope == 'duel'))
    public_name = user.display_name or f'Игрок {user.id}'
    tg_name = '@' + user.username if user.username else 'не указан'
    return f"👤 Профиль\nИгровой ник: {public_name}\nTelegram: {tg_name}\n\n🃏 Игровые очки: {int(global_score or 0)}\n⚔️ Дуэльные очки: {int(duel_score or 0)}"


async def _set_nick(db: AsyncSession, user: User, nick: str) -> str:
    nick = ' '.join((nick or '').strip().split())
    if not NICK_RE.fullmatch(nick):
        return '⚠️ Ник: 2–24 символа. Можно буквы, цифры, пробел, точку, дефис и подчёркивание.'
    user.display_name = nick
    await db.commit()
    return f'✅ Игровой ник изменён: {nick}'


async def _cmd_cards(db: AsyncSession, *, chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    allowed = await throttle.allow(f'cards:{chat_id}:{user.id}', 0.9)
    if not allowed:
        return {'ok': True, 'throttled': True}
    hand, _deck = deal_classic()
    result = evaluate_five(hand)
    await add_score(db, user_id=user.id, platform='telegram', delta=result.points, scope='global', reason='cards', source='telegram_bot', meta={'hand': hand, 'combo': result.name})
    if chat_type != 'private':
        await add_score(db, user_id=user.id, platform='telegram', delta=result.points, scope='chat', chat_id=chat_db_id, reason='cards', source='telegram_bot', meta={'hand': hand, 'combo': result.name})
    body = f"☠️ Твоя рука:\n{format_cards(hand)}\n\n{result.name} ({result.points} очков)\n{PHRASES[result.name]}"
    return await send_telegram_message(chat_id, body, reply_markup=cards_keyboard(chat_type))


async def _cmd_topscore(db: AsyncSession, *, chat_id: str, chat_type: str, chat_db_id: int) -> dict:
    if chat_type == 'private':
        items = await leaderboard(db, scope='global', limit=10)
        title = '🏆 Мировой топ игроков:'
    else:
        items = await leaderboard(db, scope='chat', chat_id=chat_db_id, limit=5)
        title = '🏆 Топ игроков в этом чате:'
    return await send_telegram_message(chat_id, format_leaderboard(items, title), reply_markup=top_keyboard(chat_type))


async def _cmd_topduel(db: AsyncSession, *, chat_id: str, chat_type: str, chat_db_id: int) -> dict:
    limit = 10 if chat_type == 'private' else 5
    items = await leaderboard(db, scope='duel', chat_id=None if chat_type == 'private' else chat_db_id, limit=limit)
    if not items:
        text = '⚔️ Дуэльный рейтинг пуст.' if chat_type == 'private' else '⚔️ Пока никто не стрелял. Начни: /duel @ник'
    else:
        text = format_leaderboard(items, '⚔️ Топ дуэлянтов:')
    return await send_telegram_message(chat_id, text, reply_markup=duel_keyboard(chat_type))


async def _cmd_duel_help(chat_id: str, chat_type: str) -> dict:
    return await send_telegram_message(chat_id, DUEL_HINT_PRIVATE if chat_type == 'private' else DUEL_HINT_GROUP, reply_markup=duel_keyboard(chat_type))


async def _finish_duel(db: AsyncSession, chat_id: str, duel_id: str, accepter_user_id: int) -> dict:
    pending = duel_manager.get(duel_id)
    if not pending:
        return await send_telegram_message(chat_id, '⏱️ Дуэль устарела. Брось новый вызов.', reply_markup=duel_keyboard('group'))
    if pending.opponent_user_id != accepter_user_id:
        return await send_telegram_message(chat_id, '⚠️ Принять вызов может только вызванный игрок.', reply_markup=duel_keyboard('group'))
    pending = duel_manager.pop(duel_id)
    if not pending:
        return await send_telegram_message(chat_id, '⏱️ Дуэль уже закрыта.', reply_markup=duel_keyboard('group'))
    table, hand_a, hand_b, _deck = deal_holdem_duel()
    res_a = best_of_seven(table, hand_a)
    res_b = best_of_seven(table, hand_b)
    duel_score = score_duel(str(pending.challenger_user_id), res_a, str(pending.opponent_user_id), res_b)
    await add_score(db, user_id=pending.challenger_user_id, platform='telegram', delta=duel_score.delta_a, scope='duel', chat_id=pending.chat_db_id, reason='duel', source='telegram_bot')
    await add_score(db, user_id=pending.opponent_user_id, platform='telegram', delta=duel_score.delta_b, scope='duel', chat_id=pending.chat_db_id, reason='duel', source='telegram_bot')
    winner = 'ничья'
    if duel_score.winner == str(pending.challenger_user_id):
        winner = pending.challenger_name
    elif duel_score.winner == str(pending.opponent_user_id):
        winner = pending.opponent_name
    body = (
        f"🎴 {pending.challenger_name} и {pending.opponent_name}, карты на стол.\n\n"
        f"Стол: {format_cards(table)}\n\n"
        f"🔷 {pending.challenger_name}: {format_cards(hand_a)} — {res_a.name} ({duel_score.delta_a:+d})\n"
        f"🔶 {pending.opponent_name}: {format_cards(hand_b)} — {res_b.name} ({duel_score.delta_b:+d})\n\n"
        f"🏆 Победитель: {winner}\n{duel_score.phrase}"
    )
    return await send_telegram_message(chat_id, body, reply_markup=duel_keyboard('group'))


async def _decline_duel(chat_id: str, duel_id: str, actor_user_id: int) -> dict:
    pending = duel_manager.get(duel_id)
    if not pending:
        return await send_telegram_message(chat_id, '⏱️ Дуэль уже неактивна.', reply_markup=duel_keyboard('group'))
    if actor_user_id not in {pending.challenger_user_id, pending.opponent_user_id}:
        return await send_telegram_message(chat_id, '⚠️ Отменить могут только участники дуэли.', reply_markup=duel_keyboard('group'))
    duel_manager.pop(duel_id)
    return await send_telegram_message(chat_id, '❌ Дуэль отменена.', reply_markup=duel_keyboard('group'))


async def _callback(update: dict, db: AsyncSession) -> list[dict] | None:
    callback = update.get('callback_query')
    if not callback:
        return None
    await answer_callback_query(str(callback.get('id') or ''), 'Принято')
    data = str(callback.get('data') or '')
    msg = callback.get('message') or {}
    chat = msg.get('chat') or {}
    chat_id = str(chat.get('id') or '')
    profile = _from_profile({'from': callback.get('from') or {}})
    user = await get_or_create_user(db, platform='telegram', **profile)

    if data.startswith('duel_accept:'):
        duel_id = data.split(':', 1)[1]
        return [await _finish_duel(db, chat_id, duel_id, user.id)]
    if data.startswith('duel_decline:'):
        duel_id = data.split(':', 1)[1]
        return [await _decline_duel(chat_id, duel_id, user.id)]

    if data == 'menu':
        data = 'start'
    fake_message = {'chat': chat, 'from': callback.get('from') or {}, 'text': '/' + data}
    update.clear()
    update['message'] = fake_message
    return None


async def handle_telegram_update(update: dict, db: AsyncSession) -> list[dict]:
    cb = await _callback(update, db)
    if cb is not None:
        return cb

    message = update.get('message') or update.get('edited_message')
    if not message:
        return []
    text = message.get('text') or ''
    cmd, args = normalize_command(text)
    chat_id = _chat_id(message)
    ctype = _chat_type(message)
    profile = _from_profile(message)
    user = await get_or_create_user(db, platform='telegram', **profile)
    chat = await get_or_create_chat(db, platform='telegram', platform_chat_id=chat_id, title=_chat_title(message), chat_type=ctype)

    if not cmd:
        return []
    if cmd == '/start':
        return [await send_telegram_message(chat_id, START_TEXT, reply_markup=main_keyboard(ctype))]
    if cmd == '/help':
        return [await send_telegram_message(chat_id, HELP_TEXT, reply_markup=main_keyboard(ctype))]
    if cmd == '/profile':
        return [await send_telegram_message(chat_id, await _profile_text(db, user), reply_markup=profile_keyboard(ctype))]
    if cmd in {'/nick_help', '/nickhelp'}:
        return [await send_telegram_message(chat_id, NICK_HINT, reply_markup=profile_keyboard(ctype))]
    if cmd == '/nick':
        if not args:
            return [await send_telegram_message(chat_id, NICK_HINT, reply_markup=profile_keyboard(ctype))]
        return [await send_telegram_message(chat_id, await _set_nick(db, user, args), reply_markup=profile_keyboard(ctype))]
    if cmd == '/cards':
        return [await _cmd_cards(db, chat_id=chat_id, chat_type=ctype, chat_db_id=chat.id, user=user)]
    if cmd == '/topscore':
        return [await _cmd_topscore(db, chat_id=chat_id, chat_type=ctype, chat_db_id=chat.id)]
    if cmd == '/topduel':
        return [await _cmd_topduel(db, chat_id=chat_id, chat_type=ctype, chat_db_id=chat.id)]
    if cmd in {'/duel_help', '/duelhelp'}:
        return [await _cmd_duel_help(chat_id, ctype)]
    if cmd == '/reset':
        return [await send_telegram_message(chat_id, '🔄 Сброс будет в админке. Сейчас очки правятся через admin API.', reply_markup=main_keyboard(ctype))]
    if cmd == '/duel':
        if ctype == 'private':
            return [await send_telegram_message(chat_id, DUEL_HINT_PRIVATE, reply_markup=duel_keyboard(ctype))]
        target = args.strip()
        if not target:
            return [await send_telegram_message(chat_id, '⚠️ Используй: /duel @никнейм', reply_markup=duel_keyboard(ctype))]
        target_username = target.lstrip('@').strip()
        if user.username and target_username.lower() == user.username.lower():
            return [await send_telegram_message(chat_id, '🪞 Себя на дуэль не вызывают. Это не храбрость, это зеркало.', reply_markup=duel_keyboard(ctype))]
        opponent = await db.scalar(select(User).where(User.username == target_username))
        if not opponent:
            return [await send_telegram_message(chat_id, '⚠️ Игрока нет в базе. Пусть сначала сыграет /cards.', reply_markup=duel_keyboard(ctype))]
        challenger_name = format_user_name(None, user.display_name, str(user.id))
        opponent_name = format_user_name(None, opponent.display_name, str(opponent.id))
        duel, error = duel_manager.create(
            chat_id=chat_id,
            chat_db_id=chat.id,
            challenger_user_id=user.id,
            opponent_user_id=opponent.id,
            challenger_name=challenger_name,
            opponent_name=opponent_name,
            ttl_seconds=60,
        )
        if error or not duel:
            return [await send_telegram_message(chat_id, '⏳ ' + (error or 'Дуэль уже ожидает ответа.'), reply_markup=duel_keyboard(ctype))]
        text = f'⚔️ {challenger_name} вызывает {opponent_name}.\n60 секунд на ответ.'
        return [await send_telegram_message(chat_id, text, reply_markup=duel_request_keyboard(duel.duel_id))]
    return [await send_telegram_message(chat_id, HELP_TEXT, reply_markup=main_keyboard(ctype))]
'''.strip() + '\n',

'app/main.py': r'''
from contextlib import asynccontextmanager, suppress
from pathlib import Path
import asyncio
import logging

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.api.admin import router as admin_router
from app.api.game import router as game_router
from app.api.health import router as health_router
from app.api.leaderboards import router as leaderboards_router
from app.api.miniapp import router as miniapp_router
from app.api.webhooks import router as webhooks_router
from app.bot.telegram_poller import telegram_polling_loop
from app.core.config import get_settings
from app.db.base import SessionLocal, init_db
from app.db.repositories import seed_defaults

logging.basicConfig(level=logging.INFO)
logging.getLogger('httpx').setLevel(logging.WARNING)
logging.getLogger('httpcore').setLevel(logging.WARNING)
log = logging.getLogger('poker_bot')

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / 'static'


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    async with SessionLocal() as db:
        await seed_defaults(db)
    task: asyncio.Task | None = None
    settings = get_settings()
    if settings.telegram_polling_enabled:
        task = asyncio.create_task(telegram_polling_loop())
        log.info('telegram polling task enabled')
    else:
        log.info('telegram polling task disabled')
    try:
        yield
    finally:
        if task:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


app = FastAPI(title='Poker Bot API', version='0.6.0', lifespan=lifespan)

app.include_router(health_router)
app.include_router(webhooks_router)
app.include_router(game_router)
app.include_router(leaderboards_router)
app.include_router(miniapp_router)
app.include_router(admin_router)
app.mount('/static', StaticFiles(directory=STATIC_DIR), name='static')


@app.get('/')
async def root():
    return {'ok': True, 'service': 'poker-bot', 'version': '0.6.0'}


@app.get('/miniapp')
async def miniapp():
    return FileResponse(STATIC_DIR / 'miniapp' / 'index.html')
'''.strip() + '\n',

'app/api/health.py': r'''
from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.base import get_db

router = APIRouter()


@router.get('/health')
async def health():
    settings = get_settings()
    return {
        'status': 'healthy',
        'service': 'poker-bot',
        'version': '0.6.0',
        'telegram_polling': bool(settings.telegram_polling_enabled),
    }


@router.get('/ready')
async def ready(db: AsyncSession = Depends(get_db)):
    await db.execute(text('SELECT 1'))
    return {'ok': True, 'db': 'ready'}
'''.strip() + '\n',

'tests/test_telegram_keyboard.py': r'''
from app.bot.common import format_leaderboard
from app.bot.duels import duel_manager
from app.bot.telegram import cards_keyboard, profile_keyboard, top_keyboard


def test_top_keyboard_has_no_nick_button():
    text = str(top_keyboard('private'))
    assert 'nick' not in text


def test_cards_keyboard_has_back_menu():
    text = str(cards_keyboard('private'))
    assert 'menu' in text


def test_profile_keyboard_has_nick_button():
    text = str(profile_keyboard('private'))
    assert 'nick_help' in text


def test_leaderboard_uses_medals_and_public_name():
    text = format_leaderboard([{'user_id': 1, 'username': 'hidden', 'display_name': 'PublicNick', 'score': 10}], 'Top')
    assert '🥇 PublicNick' in text
    assert '@hidden' not in text


def test_duel_manager_prevents_busy_players():
    a, error = duel_manager.create(chat_id='c', chat_db_id=1, challenger_user_id=1, opponent_user_id=2, challenger_name='a', opponent_name='b')
    assert a is not None
    b, error = duel_manager.create(chat_id='c', chat_db_id=1, challenger_user_id=1, opponent_user_id=3, challenger_name='a', opponent_name='c')
    assert b is None
    assert error
    duel_manager.pop(a.duel_id)
'''.strip() + '\n',
}

for path, content in files.items():
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')

print(f'WROTE {len(files)} files into {root}')
PY

python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip >/dev/null
./.venv/bin/pip install -r requirements.txt >/dev/null
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"

git add .
git commit -m "Optimize Telegram UX and pending duels stage 9" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
ai-logs poker-bot 50 | grep -E "telegram polling|telegram api|ERROR|WARNING|health" || true

echo "===== POKER BOT STAGE 9 DONE ====="
