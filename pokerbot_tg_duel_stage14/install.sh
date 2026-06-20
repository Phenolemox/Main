#!/usr/bin/env bash
set -euo pipefail

cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_stage14_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER TG DUEL STAGE14 ====="
echo "log=$LOG"

git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main
git pull --rebase origin main --quiet || true

python3 - <<'PY'
from pathlib import Path

root = Path('/opt/repos/poker-bot')
session_path = root / 'app/bot/session_state.py'
telegram_path = root / 'app/bot/telegram.py'

s = session_path.read_text(encoding='utf-8')
if 'message_id: int | None = None' not in s:
    s = s.replace('    expires_at: float = 0.0\n\n\ndef _ttl', '    expires_at: float = 0.0\n    message_id: int | None = None\n\n\ndef _ttl', 1)
if 'data["message_id"] = int(data["message_id"])' not in s:
    s = s.replace('    data["expires_at"] = float(data["expires_at"])\n    return DuelSession(**data)', '    data["expires_at"] = float(data["expires_at"])\n    if data.get("message_id") is not None:\n        data["message_id"] = int(data["message_id"])\n    return DuelSession(**data)', 1)
session_path.write_text(s, encoding='utf-8')

telegram_path.write_text(r'''from __future__ import annotations

import re

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bot.common import format_leaderboard, format_user_name, normalize_command
from app.bot.rate_limit import throttle
from app.bot.session_state import apply_exchange, sessions, toggle_selected
from app.core.config import get_settings
from app.db.models import PlatformIdentity, ScoreLedger, User
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
DUEL_HINT_PRIVATE = "⚔️ Дуэли доступны в группах. Добавь бота в чат и вызови игрока: /duel @ник"
DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Вызов живёт 5 минут. Карты приходят участникам в личку."
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
    rows.append([{'text': '🎲 Играть', 'callback_data': f'classic_done:{session_id}'}])
    return {'inline_keyboard': rows}


def duel_request_keyboard(duel_id: str) -> dict:
    return {'inline_keyboard': [[{'text': '✅ Принять', 'callback_data': f'duel_accept:{duel_id}'}, {'text': '❌ Отказаться', 'callback_data': f'duel_decline:{duel_id}'}]]}


def duel_choice_keyboard(duel_id: str, hand: list[str], selected: set[int]) -> dict:
    rows = _card_buttons('duel', duel_id, hand, selected)
    rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}])
    return {'inline_keyboard': rows}


def result_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}],
        [{'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def top_keyboard(chat_type: str = 'private') -> dict:
    rows = [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]
    if chat_type != 'private':
        rows.insert(0, [{'text': '🏆 Топ игры', 'callback_data': 'topscore'}, {'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}])
    return {'inline_keyboard': rows}


def profile_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}],
    ]}


def duel_menu_keyboard(chat_type: str = 'private') -> dict:
    if chat_type == 'private':
        return {'inline_keyboard': [
            [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
        ]}
    return {'inline_keyboard': [
        [{'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}, {'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def _chat_type(message: dict) -> str:
    return (message.get('chat') or {}).get('type') or 'private'


def _chat_id(message: dict) -> str:
    return str((message.get('chat') or {}).get('id') or '')


def _message_id(message: dict) -> int:
    return int(message.get('message_id') or 0)


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
        return {'dry_run': True, 'chat_id': str(chat_id), 'text': text, 'reply_markup': reply_markup, 'ok': True}
    payload = {'chat_id': chat_id, 'text': text, 'disable_web_page_preview': True}
    if reply_markup:
        payload['reply_markup'] = reply_markup
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f'https://api.telegram.org/bot{token}/sendMessage', json=payload)
    return {'status_code': response.status_code, 'ok': response.is_success}


async def edit_telegram_message(chat_id, message_id, text, *, reply_markup=None):
    token = get_settings().telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'ok': True}
    payload = {'chat_id': chat_id, 'message_id': message_id, 'text': text, 'disable_web_page_preview': True}
    if reply_markup:
        payload['reply_markup'] = reply_markup
    url = 'https://api.telegram.org/' + 'bot' + token + '/editMessageText'
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(url, json=payload)
    description = ''
    try:
        description = str(response.json().get('description') or '').lower()
    except Exception:
        description = ''
    if response.status_code == 400 and 'message is not modified' in description:
        return {'status_code': response.status_code, 'ok': True, 'not_modified': True}
    return {'status_code': response.status_code, 'ok': response.is_success}


async def answer_callback_query(callback_query_id: str, text: str = 'Принято', *, alert: bool = False) -> dict:
    token = get_settings().telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'ok': True}
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


async def _finish_classic(db: AsyncSession, chat_id: str, message_id: int, user_id: int, session_id: str) -> dict:
    s = sessions.pop_classic(session_id)
    if not s:
        return await edit_telegram_message(chat_id, message_id, '⏱️ Раздача устарела. Нажми /cards.', reply_markup=result_keyboard())
    if s.user_id != user_id:
        return {'ok': True, 'wrong_user': True}
    removed_text = ''
    if s.selected:
        s.hand, s.deck, removed = apply_exchange(s.hand, s.deck, s.selected)
        removed_text = f"\nСброшено: {format_cards(removed)}\n"
    result = evaluate_five(s.hand)
    await _score_classic(db, s, result)
    return await edit_telegram_message(chat_id, message_id, f"☠️ Итоговая рука:\n{format_cards(s.hand)}{removed_text}\n{result.name} ({result.points} очков)\n{PHRASES[result.name]}", reply_markup=result_keyboard(s.chat_type))


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


def _duel_status_text(duel) -> str:
    ready_count = sum(1 for v in duel.ready.values() if v)
    a_mark = '✅' if duel.ready.get(duel.challenger_user_id) else '▫️'
    b_mark = '✅' if duel.ready.get(duel.opponent_user_id) else '▫️'
    return (
        f"⚔️ Дуэль началась.\n"
        f"Стол: {format_cards(duel.table)}\n\n"
        f"{a_mark} {duel.challenger_name}\n"
        f"{b_mark} {duel.opponent_name}\n\n"
        f"Карты отправлены участникам в личку. Выберите до 2 карт и жмите 🎲 Готов.\n"
        f"Готовы: {ready_count}/2"
    )


async def _send_duel_state(chat_id: str, duel, message_id: int | None = None) -> dict:
    text = _duel_status_text(duel)
    if message_id:
        return await edit_telegram_message(chat_id, message_id, text)
    return await send_telegram_message(chat_id, text)


async def _telegram_private_chat_id(db: AsyncSession, user_id: int) -> str | None:
    ident = await db.scalar(select(PlatformIdentity).where(PlatformIdentity.platform == 'telegram', PlatformIdentity.user_id == user_id))
    return ident.platform_user_id if ident else None


async def _send_duel_private_cards(db: AsyncSession, duel, user_id: int, *, chat_id: str | None = None, message_id: int | None = None) -> dict:
    target = chat_id or await _telegram_private_chat_id(db, user_id)
    if not target:
        return {'ok': False, 'reason': 'no_private_chat'}
    hand = duel.hand_a if user_id == duel.challenger_user_id else duel.hand_b
    selected = duel.selected[user_id]
    text = f"🃏 Твои карты в дуэли:\n{format_cards(hand)}\n\nВыбрано: {len(selected)}/2."
    if duel.ready.get(user_id):
        text = f"✅ Выбор принят.\nТвои карты: {format_cards(hand)}\n\nЖдём второго игрока."
        if message_id:
            return await edit_telegram_message(target, message_id, text)
        return await send_telegram_message(target, text)
    if message_id:
        return await edit_telegram_message(target, message_id, text, reply_markup=duel_choice_keyboard(duel.duel_id, hand, selected))
    return await send_telegram_message(target, text, reply_markup=duel_choice_keyboard(duel.duel_id, hand, selected))


async def _resolve_duel(db: AsyncSession, duel_id: str) -> dict:
    duel = sessions.pop_duel(duel_id)
    if not duel:
        return await send_telegram_message('', '⏱️ Дуэль уже закрыта.', reply_markup=duel_menu_keyboard('group'))
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
    if getattr(duel, 'message_id', None):
        return await edit_telegram_message(duel.chat_id, duel.message_id, text, reply_markup=duel_menu_keyboard('group'))
    return await send_telegram_message(duel.chat_id, text, reply_markup=duel_menu_keyboard('group'))


async def _callback(update: dict, db: AsyncSession) -> list[dict] | None:
    cb = update.get('callback_query')
    if not cb:
        return None
    data = str(cb.get('data') or '')
    msg = cb.get('message') or {}
    chat = msg.get('chat') or {}
    chat_id = str(chat.get('id') or '')
    message_id = _message_id(msg)
    profile = _from_profile({'from': cb.get('from') or {}})
    user = await get_or_create_user(db, platform='telegram', **profile)
    cb_id = str(cb.get('id') or '')

    if data.startswith('classic_toggle:'):
        _, sid, idx_s = data.split(':', 2)
        s = sessions.get_classic(sid)
        if not s:
            await answer_callback_query(cb_id, 'Раздача устарела.', alert=True)
            return []
        if s.user_id != user.id:
            await answer_callback_query(cb_id, 'Это чужая раздача.', alert=True)
            return []
        ok, error = toggle_selected(s.selected, int(idx_s))
        sessions.save_classic(s)
        await answer_callback_query(cb_id, error or 'Выбрано', alert=bool(error))
        await edit_telegram_message(chat_id, message_id, f"☠️ Твоя рука:\n{format_cards(s.hand)}\n\nВыбери до 2 карт для обмена или жми 🎲 Играть.\nВыбрано: {len(s.selected)}/2", reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))
        return []

    if data.startswith('classic_done:'):
        sid = data.split(':', 1)[1]
        s = sessions.get_classic(sid)
        if s and s.user_id != user.id:
            await answer_callback_query(cb_id, 'Это чужая раздача.', alert=True)
            return []
        await answer_callback_query(cb_id, 'Играем')
        return [await _finish_classic(db, chat_id, message_id, user.id, sid)]

    if data.startswith('duel_accept:'):
        did = data.split(':', 1)[1]
        p = sessions.get_pending_duel(did)
        if not p:
            await answer_callback_query(cb_id, 'Вызов устарел.', alert=True)
            return []
        if p.opponent_user_id != user.id:
            await answer_callback_query(cb_id, 'Это не твой вызов.', alert=True)
            return []
        p = sessions.pop_pending_duel(did)
        d = sessions.start_duel(p)
        d.message_id = message_id
        sessions.save_duel(d)
        await answer_callback_query(cb_id, 'Принято')
        await _send_duel_state(chat_id, d, message_id)
        await _send_duel_private_cards(db, d, d.challenger_user_id)
        await _send_duel_private_cards(db, d, d.opponent_user_id)
        return []

    if data.startswith('duel_decline:'):
        did = data.split(':', 1)[1]
        p = sessions.get_pending_duel(did)
        if not p:
            await answer_callback_query(cb_id, 'Вызов уже закрыт.', alert=True)
            return []
        if user.id not in {p.challenger_user_id, p.opponent_user_id}:
            await answer_callback_query(cb_id, 'Это не твой вызов.', alert=True)
            return []
        sessions.pop_pending_duel(did)
        await answer_callback_query(cb_id, 'Отказ')
        await edit_telegram_message(chat_id, message_id, '❌ Дуэль отменена.', reply_markup=duel_menu_keyboard('group'))
        return []

    if data.startswith('duel_toggle:'):
        _, did, idx_s = data.split(':', 2)
        d = sessions.get_duel(did)
        if not d or user.id not in {d.challenger_user_id, d.opponent_user_id}:
            await answer_callback_query(cb_id, 'Это не твоя дуэль.', alert=True)
            return []
        if d.ready.get(user.id):
            await answer_callback_query(cb_id, 'Ты уже готов.', alert=True)
            return []
        ok, error = toggle_selected(d.selected[user.id], int(idx_s))
        sessions.save_duel(d)
        await answer_callback_query(cb_id, error or 'Выбрано', alert=bool(error))
        await _send_duel_private_cards(db, d, user.id, chat_id=chat_id, message_id=message_id)
        return []

    if data.startswith('duel_done:'):
        did = data.split(':', 1)[1]
        d = sessions.get_duel(did)
        if not d or user.id not in {d.challenger_user_id, d.opponent_user_id}:
            await answer_callback_query(cb_id, 'Это не твоя дуэль.', alert=True)
            return []
        if not d.ready.get(user.id):
            if d.selected[user.id]:
                if user.id == d.challenger_user_id:
                    d.hand_a, d.deck, _ = apply_exchange(d.hand_a, d.deck, d.selected[user.id])
                else:
                    d.hand_b, d.deck, _ = apply_exchange(d.hand_b, d.deck, d.selected[user.id])
            d.ready[user.id] = True
            sessions.save_duel(d)
        await answer_callback_query(cb_id, 'Готов')
        await _send_duel_private_cards(db, d, user.id, chat_id=chat_id, message_id=message_id)
        if all(d.ready.values()):
            return [await _resolve_duel(db, did)]
        await _send_duel_state(d.chat_id, d, getattr(d, 'message_id', None))
        return []

    await answer_callback_query(cb_id, 'Принято')
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
''', encoding='utf-8')

print('STAGE14_PATCHED_FILES=2')
PY

cat > tests/test_tg_duel_stage14.py <<'PY'
from app.bot.session_state import DuelSession, toggle_selected
from app.bot.telegram import classic_keyboard, duel_choice_keyboard, _duel_status_text


def test_classic_active_keyboard_has_no_menu_button():
    kb = classic_keyboard('sid', ['A', 'K', 'Q', 'J', '10'], set())['inline_keyboard']
    flat = [btn['callback_data'] for row in kb for btn in row]
    assert 'menu' not in flat
    assert 'classic_done:sid' in flat


def test_duel_personal_keyboard_has_cards_and_no_menu():
    kb = duel_choice_keyboard('did', ['A', 'K'], {1})['inline_keyboard']
    flat = [btn['callback_data'] for row in kb for btn in row]
    texts = [btn['text'] for row in kb for btn in row]
    assert 'duel_toggle:did:0' in flat
    assert 'duel_toggle:did:1' in flat
    assert 'duel_done:did' in flat
    assert 'menu' not in flat
    assert any(t.startswith('✅') for t in texts)


def test_toggle_selected_max_two_stage14():
    selected = set()
    assert toggle_selected(selected, 0)[0]
    assert toggle_selected(selected, 1)[0]
    ok, err = toggle_selected(selected, 2)
    assert not ok
    assert err
    assert selected == {0, 1}


def test_duel_status_text_shows_ready_count():
    d = DuelSession(
        duel_id='d', chat_id='c', chat_db_id=1,
        challenger_user_id=10, opponent_user_id=20,
        challenger_name='A', opponent_name='B',
        table=['A', 'K', 'Q', 'J', '10'], hand_a=['2', '3'], hand_b=['4', '5'], deck=[],
        selected={10: set(), 20: set()}, ready={10: True, 20: False}, expires_at=9999999999, message_id=7,
    )
    text = _duel_status_text(d)
    assert 'Готовы: 1/2' in text
    assert 'Стол:' in text
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage14_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -60 /tmp/stage14_pycompile.log; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage14_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -80 /tmp/stage14_pytest.log; exit 1; }
echo "PYTEST_OK"
tail -20 /tmp/stage14_pytest.log

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"
git add app/bot/telegram.py app/bot/session_state.py tests/test_tg_duel_stage14.py
git commit -m 'Fix Telegram duel UX stage 14' || true
git push -u origin main --quiet

a i-sync-check >/dev/null 2>&1 || true
ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage14_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage14_deploy.log; exit 1; }
echo "DEPLOY_OK"
tail -30 /tmp/stage14_deploy.log

H=$(curl -s --max-time 5 http://10.8.0.1:8140/health)
R=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)
S=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)

echo "===== STAGE14 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$H"
echo "ready=$R"
echo "sessions=$S"
ai-sync-check | tail -18
echo "POKER_TG_DUEL_STAGE14_DONE"
