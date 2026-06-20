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
git reset --hard origin/main
git clean -fd

python3 - <<'PY'
from pathlib import Path

root = Path('/opt/repos/poker-bot')

# remove stale tests that referenced old helper names
for stale in ['tests/test_telegram_keyboard.py', 'tests/test_config_stage4.py']:
    p = root / stale
    if p.exists():
        p.unlink()

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

'app/bot/session_state.py': r'''
from __future__ import annotations

import time
from dataclasses import dataclass, field
from secrets import token_urlsafe

from app.game.cards import deal_classic, deal_holdem_duel


CLASSIC_TTL_SECONDS = 300
DUEL_TTL_SECONDS = 300
MAX_SELECTED_CARDS = 2


@dataclass
class ClassicSession:
    session_id: str
    chat_id: str
    chat_db_id: int
    user_id: int
    chat_type: str
    hand: list[str]
    deck: list[str]
    selected: set[int] = field(default_factory=set)
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
    selected: dict[int, set[int]] = field(default_factory=dict)
    ready: dict[int, bool] = field(default_factory=dict)
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

    def create_classic(self, *, chat_id: str, chat_db_id: int, user_id: int, chat_type: str) -> ClassicSession:
        self.cleanup()
        sid = token_urlsafe(8)
        hand, deck = deal_classic()
        s = ClassicSession(sid, chat_id, chat_db_id, user_id, chat_type, hand, deck, expires_at=time.time() + CLASSIC_TTL_SECONDS)
        self.classic[sid] = s
        return s

    def get_classic(self, sid: str) -> ClassicSession | None:
        self.cleanup()
        return self.classic.get(sid)

    def pop_classic(self, sid: str) -> ClassicSession | None:
        self.cleanup()
        return self.classic.pop(sid, None)

    def create_pending_duel(
        self,
        *,
        chat_id: str,
        chat_db_id: int,
        challenger_user_id: int,
        opponent_user_id: int,
        challenger_name: str,
        opponent_name: str,
    ) -> tuple[PendingDuel | None, str | None]:
        self.cleanup()
        for d in self.pending_duels.values():
            if d.chat_id == chat_id and {challenger_user_id, opponent_user_id} & {d.challenger_user_id, d.opponent_user_id}:
                return None, 'У одного из игроков уже висит вызов.'
        for d in self.active_duels.values():
            if d.chat_id == chat_id and {challenger_user_id, opponent_user_id} & {d.challenger_user_id, d.opponent_user_id}:
                return None, 'У одного из игроков уже идёт дуэль.'
        did = token_urlsafe(8)
        d = PendingDuel(did, chat_id, chat_db_id, challenger_user_id, opponent_user_id, challenger_name, opponent_name, time.time() + DUEL_TTL_SECONDS)
        self.pending_duels[did] = d
        return d, None

    def get_pending_duel(self, did: str) -> PendingDuel | None:
        self.cleanup()
        return self.pending_duels.get(did)

    def pop_pending_duel(self, did: str) -> PendingDuel | None:
        self.cleanup()
        return self.pending_duels.pop(did, None)

    def start_duel(self, pending: PendingDuel) -> DuelSession:
        table, hand_a, hand_b, deck = deal_holdem_duel()
        d = DuelSession(
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
            selected={pending.challenger_user_id: set(), pending.opponent_user_id: set()},
            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},
            expires_at=time.time() + DUEL_TTL_SECONDS,
        )
        self.active_duels[d.duel_id] = d
        return d

    def get_duel(self, did: str) -> DuelSession | None:
        self.cleanup()
        return self.active_duels.get(did)

    def pop_duel(self, did: str) -> DuelSession | None:
        self.cleanup()
        return self.active_duels.pop(did, None)


def toggle_selected(selected: set[int], index: int) -> tuple[bool, str | None]:
    if index in selected:
        selected.remove(index)
        return True, None
    if len(selected) >= MAX_SELECTED_CARDS:
        return False, 'Можно выбрать максимум 2 карты. Сними одну и выбери другую.'
    selected.add(index)
    return True, None


def apply_exchange(hand: list[str], deck: list[str], selected: set[int]) -> tuple[list[str], list[str], list[str]]:
    new_hand = list(hand)
    new_deck = list(deck)
    removed: list[str] = []
    for index in sorted(selected):
        if 0 <= index < len(new_hand) and new_deck:
            removed.append(new_hand[index])
            new_hand[index] = new_deck.pop(0)
    return new_hand, new_deck, removed


sessions = SessionStore()
'''.strip() + '\n',

'app/bot/telegram.py': r'''
from __future__ import annotations

import re

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bot.common import format_leaderboard, format_user_name, normalize_command
from app.bot.rate_limit import throttle
from app.bot.session_state import apply_exchange, sessions, toggle_selected
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
DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Вызов и выбор карт живут 5 минут."
NICK_HINT = "✍️ Ник для рейтингов:\n/nick ТвойНик"
NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')


def main_keyboard(chat_type: str = 'private') -> dict:
    rows = [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}],
        [{'text': '🏆 Топ', 'callback_data': 'topscore'}, {'text': '👤 Профиль', 'callback_data': 'profile'}],
        [{'text': '📋 Помощь', 'callback_data': 'help'}],
    ]
    if chat_type != 'private':
        rows[1] = [{'text': '🏆 Топ игры', 'callback_data': 'topscore'}, {'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}]
        rows[2] = [{'text': '👤 Профиль', 'callback_data': 'profile'}, {'text': '📋 Помощь', 'callback_data': 'help'}]
    return {'inline_keyboard': rows}


def back_keyboard() -> dict:
    return {'inline_keyboard': [[{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def _card_buttons(prefix: str, session_id: str, cards: list[str], selected: set[int]) -> list[list[dict]]:
    row: list[dict] = []
    for i, card in enumerate(cards):
        mark = '✅' if i in selected else '▫️'
        row.append({'text': f'{mark}{card}', 'callback_data': f'{prefix}_toggle:{session_id}:{i}'})
    return [row]


def classic_keyboard(session_id: str, hand: list[str], selected: set[int]) -> dict:
    rows = _card_buttons('classic', session_id, hand, selected)
    rows.append([{'text': '🎲 Играть', 'callback_data': f'classic_done:{session_id}'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}])
    return {'inline_keyboard': rows}


def duel_request_keyboard(duel_id: str) -> dict:
    return {'inline_keyboard': [[{'text': '✅ Принять', 'callback_data': f'duel_accept:{duel_id}'}, {'text': '❌ Отказаться', 'callback_data': f'duel_decline:{duel_id}'}]]}


def duel_choice_keyboard(duel_id: str, hand: list[str], selected: set[int]) -> dict:
    rows = _card_buttons('duel', duel_id, hand, selected)
    rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}])
    return {'inline_keyboard': rows}


def result_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}], [{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def top_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def profile_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [[{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}]]}


def duel_menu_keyboard(chat_type: str = 'private') -> dict:
    if chat_type == 'private':
        return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}
    return {'inline_keyboard': [[{'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def _chat_type(message: dict) -> str:
    return (message.get('chat') or {}).get('type') or 'private'


def _chat_id(message: dict) -> str:
    return str((message.get('chat') or {}).get('id') or '')


def _chat_title(message: dict) -> str | None:
    chat = message.get('chat') or {}
    return chat.get('title') or chat.get('first_name') or chat.get('username')


def _from_profile(message: dict) -> dict:
    src = message.get('from') or {}
    display = ((src.get('first_name') or '') + ' ' + (src.get('last_name') or '')).strip() or src.get('username') or str(src.get('id') or 'unknown')
    return {'platform_user_id': str(src.get('id') or 'unknown'), 'username': src.get('username'), 'display_name': display, 'raw_profile': src}


async def send_telegram_message(chat_id: str | int, text: str, *, reply_markup: dict | None = None) -> dict:
    token = get_settings().telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'chat_id': str(chat_id), 'text': text, 'reply_markup': reply_markup}
    payload = {'chat_id': chat_id, 'text': text, 'disable_web_page_preview': True}
    if reply_markup:
        payload['reply_markup'] = reply_markup
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f'https://api.telegram.org/bot{token}/sendMessage', json=payload)
    return {'status_code': response.status_code, 'ok': response.is_success}


async def answer_callback_query(callback_query_id: str, text: str = 'Принято', *, alert: bool = False) -> dict:
    token = get_settings().telegram_bot_token or ''
    if not token:
        return {'dry_run': True}
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(f'https://api.telegram.org/bot{token}/answerCallbackQuery', json={'callback_query_id': callback_query_id, 'text': text, 'show_alert': alert})
    return {'status_code': response.status_code, 'ok': response.is_success}


async def _profile_text(db: AsyncSession, user: User) -> str:
    global_score = await db.scalar(select(func.coalesce(func.sum(ScoreLedger.delta), 0)).where(ScoreLedger.user_id == user.id, ScoreLedger.scope == 'global'))
    duel_score = await db.scalar(select(func.coalesce(func.sum(ScoreLedger.delta), 0)).where(ScoreLedger.user_id == user.id, ScoreLedger.scope == 'duel'))
    return f"👤 Профиль\nИгровой ник: {user.display_name or f'Игрок {user.id}'}\nTelegram: {'@' + user.username if user.username else 'не указан'}\n\n🃏 Игровые очки: {int(global_score or 0)}\n⚔️ Дуэльные очки: {int(duel_score or 0)}"


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


async def _start_classic(chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    if not await throttle.allow(f'cards:{chat_id}:{user.id}', 0.6):
        return {'ok': True, 'throttled': True}
    s = sessions.create_classic(chat_id=chat_id, chat_db_id=chat_db_id, user_id=user.id, chat_type=chat_type)
    text = f"☠️ Твоя рука:\n{format_cards(s.hand)}\n\nВыбери до 2 карт для обмена или жми 🎲 Играть."
    return await send_telegram_message(chat_id, text, reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))


async def _finish_classic(db: AsyncSession, chat_id: str, user_id: int, session_id: str) -> dict:
    s = sessions.pop_classic(session_id)
    if not s:
        return await send_telegram_message(chat_id, '⏱️ Раздача устарела. Нажми /cards.', reply_markup=result_keyboard())
    if s.user_id != user_id:
        return await send_telegram_message(chat_id, '⚠️ Это чужая раздача.', reply_markup=back_keyboard())
    removed_text = ''
    if s.selected:
        s.hand, s.deck, removed = apply_exchange(s.hand, s.deck, s.selected)
        removed_text = f"\nСброшено: {format_cards(removed)}\n"
    result = evaluate_five(s.hand)
    await _score_classic(db, s, result)
    return await send_telegram_message(chat_id, f"☠️ Итоговая рука:\n{format_cards(s.hand)}{removed_text}\n{result.name} ({result.points} очков)\n{PHRASES[result.name]}", reply_markup=result_keyboard(s.chat_type))


async def _cmd_topscore(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int) -> dict:
    if chat_type == 'private':
        items = await leaderboard(db, scope='global', limit=10)
        title = '🏆 Мировой топ игроков:'
    else:
        items = await leaderboard(db, scope='chat', chat_id=chat_db_id, limit=5)
        title = '🏆 Топ игроков в этом чате:'
    return await send_telegram_message(chat_id, format_leaderboard(items, title), reply_markup=top_keyboard(chat_type))


async def _cmd_topduel(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int) -> dict:
    items = await leaderboard(db, scope='duel', chat_id=None if chat_type == 'private' else chat_db_id, limit=10 if chat_type == 'private' else 5)
    text = format_leaderboard(items, '🛡️ Топ дуэлянтов:') if items else ('🛡️ Дуэльный рейтинг пуст.' if chat_type == 'private' else '🛡️ Пока никто не стрелял. Начни: /duel @ник')
    return await send_telegram_message(chat_id, text, reply_markup=duel_menu_keyboard(chat_type))


async def _duel_help(chat_id: str, chat_type: str) -> dict:
    return await send_telegram_message(chat_id, DUEL_HINT_PRIVATE if chat_type == 'private' else DUEL_HINT_GROUP, reply_markup=duel_menu_keyboard(chat_type))


async def _send_duel_state(chat_id: str, duel) -> dict:
    text = f"⚔️ Дуэль началась.\nСтол: {format_cards(duel.table)}\n\n{duel.challenger_name} и {duel.opponent_name}: выберите до 2 своих карт и жмите 🎲 Готов.\nГотовы: {sum(1 for v in duel.ready.values() if v)}/2"
    return await send_telegram_message(chat_id, text, reply_markup=duel_choice_keyboard(duel.duel_id, [], set()))


def duel_choice_keyboard(duel_id: str, hand: list[str], selected: set[int]) -> dict:
    # Общая клавиатура для дуэли показывает только действие. Карты выдаём персонально по клику участника.
    return {'inline_keyboard': [[{'text': '🃏 Мои карты', 'callback_data': f'duel_my:{duel_id}'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def duel_personal_keyboard(duel_id: str, hand: list[str], selected: set[int]) -> dict:
    rows = []
    row = []
    for i, card in enumerate(hand):
        mark = '✅' if i in selected else '▫️'
        row.append({'text': f'{mark}{card}', 'callback_data': f'duel_toggle:{duel_id}:{i}'})
    rows.append(row)
    rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}])
    return {'inline_keyboard': rows}


async def _resolve_duel(db: AsyncSession, chat_id: str, duel_id: str) -> dict:
    duel = sessions.pop_duel(duel_id)
    if not duel:
        return await send_telegram_message(chat_id, '⏱️ Дуэль уже закрыта.', reply_markup=duel_menu_keyboard('group'))
    res_a = best_of_seven(duel.table, duel.hand_a)
    res_b = best_of_seven(duel.table, duel.hand_b)
    score = score_duel(str(duel.challenger_user_id), res_a, str(duel.opponent_user_id), res_b)
    await add_score(db, user_id=duel.challenger_user_id, platform='telegram', delta=score.delta_a, scope='duel', chat_id=duel.chat_db_id, reason='duel', source='telegram_bot')
    await add_score(db, user_id=duel.opponent_user_id, platform='telegram', delta=score.delta_b, scope='duel', chat_id=duel.chat_db_id, reason='duel', source='telegram_bot')
    winner = 'ничья'
    if score.winner == str(duel.challenger_user_id):
        winner = duel.challenger_name
    elif score.winner == str(duel.opponent_user_id):
        winner = duel.opponent_name
    text = f"🏁 Дуэль завершена.\n\nСтол: {format_cards(duel.table)}\n\n🔷 {duel.challenger_name}: {format_cards(duel.hand_a)} — {res_a.name} ({score.delta_a:+d})\n🔶 {duel.opponent_name}: {format_cards(duel.hand_b)} — {res_b.name} ({score.delta_b:+d})\n\n🏆 Победитель: {winner}\n{score.phrase}"
    return await send_telegram_message(chat_id, text, reply_markup=duel_menu_keyboard('group'))


async def _callback(update: dict, db: AsyncSession) -> list[dict] | None:
    cb = update.get('callback_query')
    if not cb:
        return None
    data = str(cb.get('data') or '')
    msg = cb.get('message') or {}
    chat = msg.get('chat') or {}
    chat_id = str(chat.get('id') or '')
    profile = _from_profile({'from': cb.get('from') or {}})
    user = await get_or_create_user(db, platform='telegram', **profile)

    if data.startswith('classic_toggle:'):
        _, sid, idx_s = data.split(':', 2)
        s = sessions.get_classic(sid)
        if not s:
            await answer_callback_query(str(cb.get('id') or ''), 'Раздача устарела.', alert=True)
            return []
        if s.user_id != user.id:
            await answer_callback_query(str(cb.get('id') or ''), 'Это чужая раздача.', alert=True)
            return []
        ok, error = toggle_selected(s.selected, int(idx_s))
        await answer_callback_query(str(cb.get('id') or ''), error or 'Выбрано' if ok else 'Ошибка', alert=bool(error))
        return [await send_telegram_message(chat_id, f"☠️ Твоя рука:\n{format_cards(s.hand)}\n\nВыбрано: {len(s.selected)}/2", reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))]

    if data.startswith('classic_done:'):
        sid = data.split(':', 1)[1]
        s = sessions.get_classic(sid)
        if s and s.user_id != user.id:
            await answer_callback_query(str(cb.get('id') or ''), 'Это чужая раздача.', alert=True)
            return []
        await answer_callback_query(str(cb.get('id') or ''), 'Играем')
        return [await _finish_classic(db, chat_id, user.id, sid)]

    if data.startswith('duel_accept:'):
        did = data.split(':', 1)[1]
        p = sessions.get_pending_duel(did)
        if not p:
            await answer_callback_query(str(cb.get('id') or ''), 'Вызов устарел.', alert=True)
            return []
        if p.opponent_user_id != user.id:
            await answer_callback_query(str(cb.get('id') or ''), 'Принять может только вызванный игрок.', alert=True)
            return []
        await answer_callback_query(str(cb.get('id') or ''), 'Принято')
        p = sessions.pop_pending_duel(did)
        d = sessions.start_duel(p)
        return [await _send_duel_state(chat_id, d)]

    if data.startswith('duel_decline:'):
        did = data.split(':', 1)[1]
        p = sessions.get_pending_duel(did)
        if not p:
            await answer_callback_query(str(cb.get('id') or ''), 'Вызов уже закрыт.', alert=True)
            return []
        if user.id not in {p.challenger_user_id, p.opponent_user_id}:
            await answer_callback_query(str(cb.get('id') or ''), 'Отменить могут только участники.', alert=True)
            return []
        sessions.pop_pending_duel(did)
        await answer_callback_query(str(cb.get('id') or ''), 'Отказ')
        return [await send_telegram_message(chat_id, '❌ Дуэль отменена.', reply_markup=duel_menu_keyboard('group'))]

    if data.startswith('duel_my:'):
        did = data.split(':', 1)[1]
        d = sessions.get_duel(did)
        if not d or user.id not in {d.challenger_user_id, d.opponent_user_id}:
            await answer_callback_query(str(cb.get('id') or ''), 'Это не твоя дуэль.', alert=True)
            return []
        hand = d.hand_a if user.id == d.challenger_user_id else d.hand_b
        await answer_callback_query(str(cb.get('id') or ''), 'Твои карты')
        return [await send_telegram_message(chat_id, f"🃏 Твои карты:\n{format_cards(hand)}\nВыбери до 2 карт.", reply_markup=duel_personal_keyboard(d.duel_id, hand, d.selected[user.id]))]

    if data.startswith('duel_toggle:'):
        _, did, idx_s = data.split(':', 2)
        d = sessions.get_duel(did)
        if not d or user.id not in {d.challenger_user_id, d.opponent_user_id}:
            await answer_callback_query(str(cb.get('id') or ''), 'Это не твоя дуэль.', alert=True)
            return []
        if d.ready.get(user.id):
            await answer_callback_query(str(cb.get('id') or ''), 'Ты уже готов.', alert=True)
            return []
        ok, error = toggle_selected(d.selected[user.id], int(idx_s))
        await answer_callback_query(str(cb.get('id') or ''), error or 'Выбрано', alert=bool(error))
        hand = d.hand_a if user.id == d.challenger_user_id else d.hand_b
        return [await send_telegram_message(chat_id, f"🃏 Твои карты:\n{format_cards(hand)}\nВыбрано: {len(d.selected[user.id])}/2", reply_markup=duel_personal_keyboard(d.duel_id, hand, d.selected[user.id]))]

    if data.startswith('duel_done:'):
        did = data.split(':', 1)[1]
        d = sessions.get_duel(did)
        if not d or user.id not in {d.challenger_user_id, d.opponent_user_id}:
            await answer_callback_query(str(cb.get('id') or ''), 'Это не твоя дуэль.', alert=True)
            return []
        if not d.ready.get(user.id):
            if d.selected[user.id]:
                if user.id == d.challenger_user_id:
                    d.hand_a, d.deck, _ = apply_exchange(d.hand_a, d.deck, d.selected[user.id])
                else:
                    d.hand_b, d.deck, _ = apply_exchange(d.hand_b, d.deck, d.selected[user.id])
            d.ready[user.id] = True
        await answer_callback_query(str(cb.get('id') or ''), 'Готов')
        if all(d.ready.values()):
            return [await _resolve_duel(db, chat_id, did)]
        return [await _send_duel_state(chat_id, d)]

    await answer_callback_query(str(cb.get('id') or ''), 'Принято')
    if data == 'menu':
        data = 'start'
    update.clear()
    update['message'] = {'chat': chat, 'from': cb.get('from') or {}, 'text': '/' + data}
    return None


async def handle_telegram_update(update: dict, db: AsyncSession) -> list[dict]:
    callback_result = await _callback(update, db)
    if callback_result is not None:
        return callback_result
    msg = update.get('message') or update.get('edited_message')
    if not msg:
        return []
    cmd, args = normalize_command(msg.get('text') or '')
    chat_id = _chat_id(msg)
    ctype = _chat_type(msg)
    profile = _from_profile(msg)
    user = await get_or_create_user(db, platform='telegram', **profile)
    chat = await get_or_create_chat(db, platform='telegram', platform_chat_id=chat_id, title=_chat_title(msg), chat_type=ctype)

    if cmd == '/start':
        return [await send_telegram_message(chat_id, START_TEXT, reply_markup=main_keyboard(ctype))]
    if cmd == '/help':
        return [await send_telegram_message(chat_id, HELP_TEXT, reply_markup=back_keyboard())]
    if cmd == '/profile':
        return [await send_telegram_message(chat_id, await _profile_text(db, user), reply_markup=profile_keyboard(ctype))]
    if cmd in {'/nick_help', '/nickhelp'}:
        return [await send_telegram_message(chat_id, NICK_HINT, reply_markup=profile_keyboard(ctype))]
    if cmd == '/nick':
        return [await send_telegram_message(chat_id, await _set_nick(db, user, args) if args else NICK_HINT, reply_markup=profile_keyboard(ctype))]
    if cmd == '/cards':
        return [await _start_classic(chat_id, ctype, chat.id, user)]
    if cmd == '/topscore':
        return [await _cmd_topscore(db, chat_id, ctype, chat.id)]
    if cmd == '/topduel':
        return [await _cmd_topduel(db, chat_id, ctype, chat.id)]
    if cmd in {'/duel_help', '/duelhelp'}:
        return [await _duel_help(chat_id, ctype)]
    if cmd == '/reset':
        return [await send_telegram_message(chat_id, '🔄 Сброс будет в админке.', reply_markup=back_keyboard())]
    if cmd == '/duel':
        if ctype == 'private':
            return [await send_telegram_message(chat_id, DUEL_HINT_PRIVATE, reply_markup=duel_menu_keyboard(ctype))]
        if not args.strip():
            return [await send_telegram_message(chat_id, '⚠️ Используй: /duel @никнейм', reply_markup=duel_menu_keyboard(ctype))]
        target_username = args.strip().lstrip('@')
        if user.username and target_username.lower() == user.username.lower():
            return [await send_telegram_message(chat_id, '🪞 Себя на дуэль не вызывают.', reply_markup=duel_menu_keyboard(ctype))]
        opponent = await db.scalar(select(User).where(User.username == target_username))
        if not opponent:
            return [await send_telegram_message(chat_id, '⚠️ Игрока нет в базе. Пусть сначала сыграет /cards.', reply_markup=duel_menu_keyboard(ctype))]
        d, error = sessions.create_pending_duel(
            chat_id=chat_id,
            chat_db_id=chat.id,
            challenger_user_id=user.id,
            opponent_user_id=opponent.id,
            challenger_name=format_user_name(None, user.display_name, str(user.id)),
            opponent_name=format_user_name(None, opponent.display_name, str(opponent.id)),
        )
        if error or not d:
            return [await send_telegram_message(chat_id, '⏳ ' + (error or 'Дуэль уже ожидает ответа.'), reply_markup=duel_menu_keyboard(ctype))]
        return [await send_telegram_message(chat_id, f'⚔️ {d.challenger_name} вызывает {d.opponent_name}.\n5 минут на ответ.', reply_markup=duel_request_keyboard(d.duel_id))]
    return []
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


app = FastAPI(title='Poker Bot API', version='0.8.0', lifespan=lifespan)
app.include_router(health_router)
app.include_router(webhooks_router)
app.include_router(game_router)
app.include_router(leaderboards_router)
app.include_router(miniapp_router)
app.include_router(admin_router)
app.mount('/static', StaticFiles(directory=STATIC_DIR), name='static')


@app.get('/')
async def root():
    return {'ok': True, 'service': 'poker-bot', 'version': '0.8.0'}


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
    s = get_settings()
    return {'status': 'healthy', 'service': 'poker-bot', 'version': '0.8.0', 'telegram_polling': bool(s.telegram_polling_enabled)}


@router.get('/ready')
async def ready(db: AsyncSession = Depends(get_db)):
    await db.execute(text('SELECT 1'))
    return {'ok': True, 'db': 'ready'}
'''.strip() + '\n',

'tests/test_stage11_select_cards.py': r'''
from app.bot.session_state import apply_exchange, toggle_selected
from app.bot.telegram import classic_keyboard


def test_toggle_max_two():
    selected = set()
    assert toggle_selected(selected, 0)[0]
    assert toggle_selected(selected, 1)[0]
    ok, err = toggle_selected(selected, 2)
    assert not ok
    assert err
    assert selected == {0, 1}


def test_apply_exchange_selected_indexes():
    hand = ['♠A', '♥K', '♦Q', '♣J', '♠10']
    deck = ['♣2', '♦3', '♥4']
    new_hand, new_deck, removed = apply_exchange(hand, deck, {1, 3})
    assert removed == ['♥K', '♣J']
    assert new_hand == ['♠A', '♣2', '♦Q', '♦3', '♠10']
    assert new_deck == ['♥4']


def test_classic_keyboard_has_card_buttons():
    kb = classic_keyboard('s', ['♠A', '♥K', '♦Q', '♣J', '♠10'], {0})
    text = str(kb)
    assert 'classic_toggle:s:0' in text
    assert '✅♠A' in text
    assert 'classic_done:s' in text
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
git commit -m "Add explicit card selection exchange stage 11" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
ai-logs poker-bot 50 | grep -E "telegram polling|telegram api|ERROR|WARNING|health" || true

echo "===== POKER BOT STAGE 11 DONE ====="
