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
'app/bot/session_state.py': r'''
from __future__ import annotations

import time
from dataclasses import dataclass, field
from secrets import token_urlsafe
from typing import Literal

from app.game.cards import best_of_seven, deal_classic, deal_holdem_duel, evaluate_five, shuffle_deck


@dataclass
class ClassicSession:
    session_id: str
    chat_id: str
    chat_db_id: int
    user_id: int
    platform: str
    chat_type: str
    hand: list[str]
    deck: list[str]
    exchanged: bool = False
    created_at: float = field(default_factory=time.time)
    expires_at: float = 0.0


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


@dataclass
class DuelSession:
    duel_id: str
    chat_id: str
    chat_db_id: int
    challenger_user_id: int
    opponent_user_id: int
    challenger_name: str
    opponent_name: str
    table: list[str]
    hand_a: list[str]
    hand_b: list[str]
    deck: list[str]
    exchanged: dict[int, bool] = field(default_factory=dict)
    ready: dict[int, bool] = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)
    expires_at: float = 0.0


class SessionStore:
    def __init__(self) -> None:
        self.classic: dict[str, ClassicSession] = {}
        self.pending_duels: dict[str, PendingDuel] = {}
        self.active_duels: dict[str, DuelSession] = {}

    def cleanup(self) -> None:
        now = time.time()
        self.classic = {k: v for k, v in self.classic.items() if v.expires_at > now}
        self.pending_duels = {k: v for k, v in self.pending_duels.items() if v.expires_at > now}
        self.active_duels = {k: v for k, v in self.active_duels.items() if v.expires_at > now}

    def create_classic(self, *, chat_id: str, chat_db_id: int, user_id: int, platform: str, chat_type: str, ttl: int = 120) -> ClassicSession:
        self.cleanup()
        session_id = token_urlsafe(8)
        hand, deck = deal_classic()
        s = ClassicSession(session_id, chat_id, chat_db_id, user_id, platform, chat_type, hand, deck, expires_at=time.time() + ttl)
        self.classic[session_id] = s
        return s

    def pop_classic(self, session_id: str) -> ClassicSession | None:
        self.cleanup()
        return self.classic.pop(session_id, None)

    def get_classic(self, session_id: str) -> ClassicSession | None:
        self.cleanup()
        return self.classic.get(session_id)

    def create_pending_duel(
        self,
        *,
        chat_id: str,
        chat_db_id: int,
        challenger_user_id: int,
        opponent_user_id: int,
        challenger_name: str,
        opponent_name: str,
        ttl: int = 300,
    ) -> tuple[PendingDuel | None, str | None]:
        self.cleanup()
        for duel in self.pending_duels.values():
            if duel.chat_id != chat_id:
                continue
            busy = {duel.challenger_user_id, duel.opponent_user_id}
            if challenger_user_id in busy or opponent_user_id in busy:
                return None, 'У одного из игроков уже висит вызов.'
        for duel in self.active_duels.values():
            if duel.chat_id != chat_id:
                continue
            busy = {duel.challenger_user_id, duel.opponent_user_id}
            if challenger_user_id in busy or opponent_user_id in busy:
                return None, 'У одного из игроков уже идёт дуэль.'
        duel_id = token_urlsafe(8)
        duel = PendingDuel(duel_id, chat_id, chat_db_id, challenger_user_id, opponent_user_id, challenger_name, opponent_name, time.time(), time.time() + ttl)
        self.pending_duels[duel_id] = duel
        return duel, None

    def pop_pending_duel(self, duel_id: str) -> PendingDuel | None:
        self.cleanup()
        return self.pending_duels.pop(duel_id, None)

    def get_pending_duel(self, duel_id: str) -> PendingDuel | None:
        self.cleanup()
        return self.pending_duels.get(duel_id)

    def start_duel(self, pending: PendingDuel, ttl: int = 300) -> DuelSession:
        table, hand_a, hand_b, deck = deal_holdem_duel()
        duel = DuelSession(
            duel_id=pending.duel_id,
            chat_id=pending.chat_id,
            chat_db_id=pending.chat_db_id,
            challenger_user_id=pending.challenger_user_id,
            opponent_user_id=pending.opponent_user_id,
            challenger_name=pending.challenger_name,
            opponent_name=pending.opponent_name,
            table=table,
            hand_a=hand_a,
            hand_b=hand_b,
            deck=deck,
            exchanged={pending.challenger_user_id: False, pending.opponent_user_id: False},
            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},
            expires_at=time.time() + ttl,
        )
        self.active_duels[duel.duel_id] = duel
        return duel

    def get_duel(self, duel_id: str) -> DuelSession | None:
        self.cleanup()
        return self.active_duels.get(duel_id)

    def pop_duel(self, duel_id: str) -> DuelSession | None:
        self.cleanup()
        return self.active_duels.pop(duel_id, None)


def exchange_two_cards(hand: list[str], deck: list[str]) -> tuple[list[str], list[str], list[str]]:
    # Быстро и без перегруза интерфейса: меняем две самые слабые карты.
    from app.game.cards import parse_card
    indexed = list(enumerate(hand))
    indexed.sort(key=lambda item: parse_card(item[1])[2])
    replace_indexes = sorted(i for i, _ in indexed[:2])
    removed = [hand[i] for i in replace_indexes]
    new_hand = list(hand)
    new_deck = list(deck)
    for i in replace_indexes:
        new_hand[i] = new_deck.pop(0)
    return new_hand, new_deck, removed


sessions = SessionStore()
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
from app.bot.rate_limit import throttle
from app.bot.session_state import exchange_two_cards, sessions
from app.core.config import get_settings
from app.db.models import ScoreLedger, User
from app.db.repositories import add_score, get_or_create_chat, get_or_create_user, leaderboard
from app.game.cards import PHRASES, best_of_seven, evaluate_five, format_cards
from app.game.scoring import score_duel

HELP_TEXT = """📋 Команды:
/start — меню
/cards — раздача с обменом
/topscore — рейтинг игры
/topduel — рейтинг дуэлей
/profile — профиль
/nick Имя — игровой ник
/duel @ник — дуэль в группе"""

START_TEXT = "🎰 Добро пожаловать за стол. Сделай ход."
DUEL_HINT_PRIVATE = "⚔️ Дуэли работают в группах. Добавь бота в чат и вызови игрока: /duel @ник"
DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Вызов висит 5 минут. После принятия каждый может оставить карты или обменять 2."
NICK_HINT = "✍️ Ник для рейтингов:\n/nick ТвойНик"
NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')


def main_keyboard(chat_type: str = 'private') -> dict:
    rows = [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}],
        [{'text': '🏆 Топ', 'callback_data': 'topscore'}, {'text': '👤 Профиль', 'callback_data': 'profile'}],
        [{'text': '📋 Помощь', 'callback_data': 'help'}],
    ]
    if chat_type != 'private':
        rows[1] = [{'text': '🏆 Топ игры', 'callback_data': 'topscore'}, {'text': '⚔️ Топ дуэлей', 'callback_data': 'topduel'}]
        rows[2] = [{'text': '👤 Профиль', 'callback_data': 'profile'}, {'text': '📋 Помощь', 'callback_data': 'help'}]
    return {'inline_keyboard': rows}


def menu_back_keyboard() -> dict:
    return {'inline_keyboard': [[{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def classic_decision_keyboard(session_id: str) -> dict:
    return {'inline_keyboard': [[
        {'text': '✅ Оставить', 'callback_data': f'classic_keep:{session_id}'},
        {'text': '🔁 Обменять 2', 'callback_data': f'classic_swap:{session_id}'},
    ], [{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def after_result_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}],
        [{'text': '🏆 Топ', 'callback_data': 'topscore'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def top_keyboard(chat_type: str = 'private') -> dict:
    if chat_type == 'private':
        return {'inline_keyboard': [[{'text': '🏆 Мировой топ', 'callback_data': 'topscore'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}
    return {'inline_keyboard': [[{'text': '🏆 Топ игры', 'callback_data': 'topscore'}, {'text': '⚔️ Топ дуэлей', 'callback_data': 'topduel'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def profile_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [[{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}]]}


def duel_keyboard(chat_type: str = 'private') -> dict:
    if chat_type == 'private':
        return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}
    return {'inline_keyboard': [[{'text': '⚔️ Топ дуэлей', 'callback_data': 'topduel'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def duel_request_keyboard(duel_id: str) -> dict:
    return {'inline_keyboard': [[{'text': '✅ Принять', 'callback_data': f'duel_accept:{duel_id}'}, {'text': '❌ Отказаться', 'callback_data': f'duel_decline:{duel_id}'}]]}


def duel_decision_keyboard(duel_id: str) -> dict:
    return {'inline_keyboard': [[{'text': '✅ Оставить мои', 'callback_data': f'duel_keep:{duel_id}'}, {'text': '🔁 Обменять 2 мои', 'callback_data': f'duel_swap:{duel_id}'}]]}


def _chat_type(message: dict) -> str:
    return (message.get('chat') or {}).get('type') or 'private'


def _chat_id(message: dict) -> str:
    return str((message.get('chat') or {}).get('id') or '')


def _chat_title(message: dict) -> str | None:
    chat = message.get('chat') or {}
    return chat.get('title') or chat.get('first_name') or chat.get('username')


def _from_profile(message: dict) -> dict:
    src = message.get('from') or {}
    first = src.get('first_name') or ''
    last = src.get('last_name') or ''
    display = (first + ' ' + last).strip() or src.get('username') or str(src.get('id') or 'unknown')
    return {'platform_user_id': str(src.get('id') or 'unknown'), 'username': src.get('username'), 'display_name': display, 'raw_profile': src}


async def send_telegram_message(chat_id: str | int, text: str, *, reply_markup: dict | None = None) -> dict:
    settings = get_settings()
    token = settings.telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'chat_id': str(chat_id), 'text': text, 'reply_markup': reply_markup}
    payload = {'chat_id': chat_id, 'text': text, 'disable_web_page_preview': True}
    if reply_markup:
        payload['reply_markup'] = reply_markup
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f'https://api.telegram.org/bot{token}/sendMessage', json=payload)
    return {'status_code': response.status_code, 'ok': response.is_success}


async def answer_callback_query(callback_query_id: str, text: str = 'Принято', *, alert: bool = False) -> dict:
    settings = get_settings()
    token = settings.telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'callback_query_id': callback_query_id, 'text': text}
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(f'https://api.telegram.org/bot{token}/answerCallbackQuery', json={'callback_query_id': callback_query_id, 'text': text, 'show_alert': alert})
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


async def _score_classic(db: AsyncSession, s, result) -> None:
    await add_score(db, user_id=s.user_id, platform='telegram', delta=result.points, scope='global', reason='cards', source='telegram_bot', meta={'hand': s.hand, 'combo': result.name})
    if s.chat_type != 'private':
        await add_score(db, user_id=s.user_id, platform='telegram', delta=result.points, scope='chat', chat_id=s.chat_db_id, reason='cards', source='telegram_bot', meta={'hand': s.hand, 'combo': result.name})


async def _start_classic(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    if not await throttle.allow(f'cards:{chat_id}:{user.id}', 0.6):
        return {'ok': True, 'throttled': True}
    s = sessions.create_classic(chat_id=chat_id, chat_db_id=chat_db_id, user_id=user.id, platform='telegram', chat_type=chat_type, ttl=120)
    text = f"☠️ Твоя рука:\n{format_cards(s.hand)}\n\nОставить или обменять 2 слабые карты?"
    return await send_telegram_message(chat_id, text, reply_markup=classic_decision_keyboard(s.session_id))


async def _finish_classic(db: AsyncSession, chat_id: str, user_id: int, session_id: str, *, swap: bool) -> dict | None:
    s = sessions.get_classic(session_id)
    if not s:
        return await send_telegram_message(chat_id, '⏱️ Раздача устарела. Нажми /cards.', reply_markup=after_result_keyboard())
    if s.user_id != user_id:
        await answer_callback_query('', '')
        return None
    s = sessions.pop_classic(session_id)
    assert s is not None
    removed_text = ''
    if swap:
        s.hand, s.deck, removed = exchange_two_cards(s.hand, s.deck)
        removed_text = f"\nСброшено: {format_cards(removed)}\n"
    result = evaluate_five(s.hand)
    await _score_classic(db, s, result)
    text = f"☠️ Итоговая рука:\n{format_cards(s.hand)}{removed_text}\n{result.name} ({result.points} очков)\n{PHRASES[result.name]}"
    return await send_telegram_message(chat_id, text, reply_markup=after_result_keyboard(s.chat_type))


async def _cmd_topscore(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int) -> dict:
    if chat_type == 'private':
        items = await leaderboard(db, scope='global', limit=10)
        title = '🏆 Мировой топ игроков:'
    else:
        items = await leaderboard(db, scope='chat', chat_id=chat_db_id, limit=5)
        title = '🏆 Топ игроков в этом чате:'
    return await send_telegram_message(chat_id, format_leaderboard(items, title), reply_markup=top_keyboard(chat_type))


async def _cmd_topduel(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int) -> dict:
    limit = 10 if chat_type == 'private' else 5
    items = await leaderboard(db, scope='duel', chat_id=None if chat_type == 'private' else chat_db_id, limit=limit)
    text = format_leaderboard(items, '⚔️ Топ дуэлянтов:') if items else ('⚔️ Дуэльный рейтинг пуст.' if chat_type == 'private' else '⚔️ Пока никто не стрелял. Начни: /duel @ник')
    return await send_telegram_message(chat_id, text, reply_markup=duel_keyboard(chat_type))


async def _duel_help(chat_id: str, chat_type: str) -> dict:
    return await send_telegram_message(chat_id, DUEL_HINT_PRIVATE if chat_type == 'private' else DUEL_HINT_GROUP, reply_markup=duel_keyboard(chat_type))


async def _send_duel_state(chat_id: str, duel) -> dict:
    text = (
        f"⚔️ Дуэль началась.\n"
        f"{duel.challenger_name} и {duel.opponent_name}, решите: оставить карты или обменять 2.\n\n"
        f"Стол: {format_cards(duel.table)}\n"
        f"Статус: {sum(1 for v in duel.ready.values() if v)}/2 готовы"
    )
    return await send_telegram_message(chat_id, text, reply_markup=duel_decision_keyboard(duel.duel_id))


async def _resolve_duel(db: AsyncSession, chat_id: str, duel_id: str) -> dict:
    duel = sessions.pop_duel(duel_id)
    if not duel:
        return await send_telegram_message(chat_id, '⏱️ Дуэль уже закрыта.', reply_markup=duel_keyboard('group'))
    res_a = best_of_seven(duel.table, duel.hand_a)
    res_b = best_of_seven(duel.table, duel.hand_b)
    duel_score = score_duel(str(duel.challenger_user_id), res_a, str(duel.opponent_user_id), res_b)
    await add_score(db, user_id=duel.challenger_user_id, platform='telegram', delta=duel_score.delta_a, scope='duel', chat_id=duel.chat_db_id, reason='duel', source='telegram_bot')
    await add_score(db, user_id=duel.opponent_user_id, platform='telegram', delta=duel_score.delta_b, scope='duel', chat_id=duel.chat_db_id, reason='duel', source='telegram_bot')
    winner = 'ничья'
    if duel_score.winner == str(duel.challenger_user_id):
        winner = duel.challenger_name
    elif duel_score.winner == str(duel.opponent_user_id):
        winner = duel.opponent_name
    body = (
        f"🏁 Дуэль завершена.\n\n"
        f"Стол: {format_cards(duel.table)}\n\n"
        f"🔷 {duel.challenger_name}: {format_cards(duel.hand_a)} — {res_a.name} ({duel_score.delta_a:+d})\n"
        f"🔶 {duel.opponent_name}: {format_cards(duel.hand_b)} — {res_b.name} ({duel_score.delta_b:+d})\n\n"
        f"🏆 Победитель: {winner}\n{duel_score.phrase}"
    )
    return await send_telegram_message(chat_id, body, reply_markup=duel_keyboard('group'))


async def _callback(update: dict, db: AsyncSession) -> list[dict] | None:
    callback = update.get('callback_query')
    if not callback:
        return None
    data = str(callback.get('data') or '')
    msg = callback.get('message') or {}
    chat = msg.get('chat') or {}
    chat_id = str(chat.get('id') or '')
    profile = _from_profile({'from': callback.get('from') or {}})
    user = await get_or_create_user(db, platform='telegram', **profile)

    if data.startswith('classic_keep:') or data.startswith('classic_swap:'):
        session_id = data.split(':', 1)[1]
        s = sessions.get_classic(session_id)
        if s and s.user_id != user.id:
            await answer_callback_query(str(callback.get('id') or ''), 'Это чужая раздача.', alert=True)
            return []
        await answer_callback_query(str(callback.get('id') or ''), 'Принято')
        return [r] if (r := await _finish_classic(db, chat_id, user.id, session_id, swap=data.startswith('classic_swap:'))) else []

    if data.startswith('duel_accept:'):
        duel_id = data.split(':', 1)[1]
        pending = sessions.get_pending_duel(duel_id)
        if not pending:
            await answer_callback_query(str(callback.get('id') or ''), 'Вызов устарел.', alert=True)
            return []
        if pending.opponent_user_id != user.id:
            await answer_callback_query(str(callback.get('id') or ''), 'Принять может только вызванный игрок.', alert=True)
            return []
        await answer_callback_query(str(callback.get('id') or ''), 'Дуэль принята')
        pending = sessions.pop_pending_duel(duel_id)
        duel = sessions.start_duel(pending)
        return [await _send_duel_state(chat_id, duel)]

    if data.startswith('duel_decline:'):
        duel_id = data.split(':', 1)[1]
        pending = sessions.get_pending_duel(duel_id)
        if not pending:
            await answer_callback_query(str(callback.get('id') or ''), 'Вызов уже закрыт.', alert=True)
            return []
        if user.id not in {pending.challenger_user_id, pending.opponent_user_id}:
            await answer_callback_query(str(callback.get('id') or ''), 'Отменить могут только участники.', alert=True)
            return []
        await answer_callback_query(str(callback.get('id') or ''), 'Отказ')
        sessions.pop_pending_duel(duel_id)
        return [await send_telegram_message(chat_id, '❌ Дуэль отменена.', reply_markup=duel_keyboard('group'))]

    if data.startswith('duel_keep:') or data.startswith('duel_swap:'):
        duel_id = data.split(':', 1)[1]
        duel = sessions.get_duel(duel_id)
        if not duel:
            await answer_callback_query(str(callback.get('id') or ''), 'Дуэль устарела.', alert=True)
            return []
        if user.id not in {duel.challenger_user_id, duel.opponent_user_id}:
            await answer_callback_query(str(callback.get('id') or ''), 'Это не твоя дуэль.', alert=True)
            return []
        if duel.ready.get(user.id):
            await answer_callback_query(str(callback.get('id') or ''), 'Ты уже выбрал.', alert=True)
            return []
        if data.startswith('duel_swap:') and not duel.exchanged.get(user.id):
            if user.id == duel.challenger_user_id:
                duel.hand_a, duel.deck, _removed = exchange_two_cards(duel.hand_a, duel.deck)
            else:
                duel.hand_b, duel.deck, _removed = exchange_two_cards(duel.hand_b, duel.deck)
            duel.exchanged[user.id] = True
        duel.ready[user.id] = True
        await answer_callback_query(str(callback.get('id') or ''), 'Принято')
        if all(duel.ready.values()):
            return [await _resolve_duel(db, chat_id, duel_id)]
        return [await _send_duel_state(chat_id, duel)]

    await answer_callback_query(str(callback.get('id') or ''), 'Принято')
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
        return [await send_telegram_message(chat_id, HELP_TEXT, reply_markup=menu_back_keyboard())]
    if cmd == '/profile':
        return [await send_telegram_message(chat_id, await _profile_text(db, user), reply_markup=profile_keyboard(ctype))]
    if cmd in {'/nick_help', '/nickhelp'}:
        return [await send_telegram_message(chat_id, NICK_HINT, reply_markup=profile_keyboard(ctype))]
    if cmd == '/nick':
        return [await send_telegram_message(chat_id, await _set_nick(db, user, args) if args else NICK_HINT, reply_markup=profile_keyboard(ctype))]
    if cmd == '/cards':
        return [await _start_classic(db, chat_id, ctype, chat.id, user)]
    if cmd == '/topscore':
        return [await _cmd_topscore(db, chat_id, ctype, chat.id)]
    if cmd == '/topduel':
        return [await _cmd_topduel(db, chat_id, ctype, chat.id)]
    if cmd in {'/duel_help', '/duelhelp'}:
        return [await _duel_help(chat_id, ctype)]
    if cmd == '/reset':
        return [await send_telegram_message(chat_id, '🔄 Сброс будет в админке.', reply_markup=menu_back_keyboard())]
    if cmd == '/duel':
        if ctype == 'private':
            return [await send_telegram_message(chat_id, DUEL_HINT_PRIVATE, reply_markup=duel_keyboard(ctype))]
        if not args.strip():
            return [await send_telegram_message(chat_id, '⚠️ Используй: /duel @никнейм', reply_markup=duel_keyboard(ctype))]
        target_username = args.strip().lstrip('@')
        if user.username and target_username.lower() == user.username.lower():
            return [await send_telegram_message(chat_id, '🪞 Себя на дуэль не вызывают.', reply_markup=duel_keyboard(ctype))]
        opponent = await db.scalar(select(User).where(User.username == target_username))
        if not opponent:
            return [await send_telegram_message(chat_id, '⚠️ Игрока нет в базе. Пусть сначала сыграет /cards.', reply_markup=duel_keyboard(ctype))]
        challenger_name = format_user_name(None, user.display_name, str(user.id))
        opponent_name = format_user_name(None, opponent.display_name, str(opponent.id))
        duel, error = sessions.create_pending_duel(chat_id=chat_id, chat_db_id=chat.id, challenger_user_id=user.id, opponent_user_id=opponent.id, challenger_name=challenger_name, opponent_name=opponent_name, ttl=300)
        if error or not duel:
            return [await send_telegram_message(chat_id, '⏳ ' + (error or 'Дуэль уже ожидает ответа.'), reply_markup=duel_keyboard(ctype))]
        return [await send_telegram_message(chat_id, f'⚔️ {challenger_name} вызывает {opponent_name}.\n5 минут на ответ.', reply_markup=duel_request_keyboard(duel.duel_id))]
    return [await send_telegram_message(chat_id, HELP_TEXT, reply_markup=menu_back_keyboard())]
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


app = FastAPI(title='Poker Bot API', version='0.7.0', lifespan=lifespan)

app.include_router(health_router)
app.include_router(webhooks_router)
app.include_router(game_router)
app.include_router(leaderboards_router)
app.include_router(miniapp_router)
app.include_router(admin_router)
app.mount('/static', StaticFiles(directory=STATIC_DIR), name='static')


@app.get('/')
async def root():
    return {'ok': True, 'service': 'poker-bot', 'version': '0.7.0'}


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
    return {'status': 'healthy', 'service': 'poker-bot', 'version': '0.7.0', 'telegram_polling': bool(settings.telegram_polling_enabled)}


@router.get('/ready')
async def ready(db: AsyncSession = Depends(get_db)):
    await db.execute(text('SELECT 1'))
    return {'ok': True, 'db': 'ready'}
'''.strip() + '\n',

'tests/test_stage10_sessions.py': r'''
from app.bot.session_state import exchange_two_cards, sessions
from app.bot.telegram import classic_decision_keyboard, duel_decision_keyboard


def test_exchange_two_cards_replaces_two():
    hand = ['♠2', '♥3', '♦A', '♣K', '♠Q']
    deck = ['♣9', '♦10', '♥J']
    new_hand, new_deck, removed = exchange_two_cards(hand, deck)
    assert len(removed) == 2
    assert len(new_hand) == 5
    assert len(new_deck) == 1


def test_classic_keyboard_has_keep_and_swap():
    text = str(classic_decision_keyboard('x'))
    assert 'classic_keep' in text
    assert 'classic_swap' in text


def test_duel_keyboard_has_keep_and_swap():
    text = str(duel_decision_keyboard('x'))
    assert 'duel_keep' in text
    assert 'duel_swap' in text
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
git commit -m "Add card exchange and guarded duel flow stage 10" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
ai-logs poker-bot 50 | grep -E "telegram polling|telegram api|ERROR|WARNING|health" || true

echo "===== POKER BOT STAGE 10 DONE ====="
