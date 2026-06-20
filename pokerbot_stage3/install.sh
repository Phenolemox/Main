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
from textwrap import dedent

root = Path('/opt/repos/poker-bot')
files = {
'app/bot/__init__.py': '# bot adapters package\n',

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
    if username:
        return '@' + username
    if display_name:
        return display_name
    return fallback


def format_leaderboard(items: list[dict], title: str) -> str:
    if not items:
        return '🐍 Пока никто не играл.'
    lines = [title]
    for idx, item in enumerate(items, start=1):
        name = item.get('username') or item.get('display_name') or ('user_' + str(item.get('user_id')))
        if item.get('username'):
            name = '@' + name
        lines.append(f"{idx}. {name} — {item.get('score', 0)} очков")
    return '\n'.join(lines)
'''.strip() + '\n',

'app/bot/telegram.py': r'''
from __future__ import annotations

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bot.common import format_leaderboard, format_user_name, normalize_command
from app.core.config import get_settings
from app.db.models import User
from app.db.repositories import add_score, get_or_create_chat, get_or_create_user, leaderboard
from app.game.cards import PHRASES, best_of_seven, deal_classic, deal_holdem_duel, evaluate_five, format_cards
from app.game.scoring import score_duel


HELP_TEXT = """📋 Доступные команды:
/start — начать работу с ботом
/cards — раздать новые карты и начать игру
/topscore — показать таблицу лидеров
/topduel — показать таблицу дуэлей
/reset — сбросить очки, пока только владелец
/duel @никнейм — бросить вызов на дуэль в группе
/help — показать справку"""

START_TEXT = "🎰 Добро пожаловать за стол! Используй /cards чтобы сыграть."


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


async def send_telegram_message(chat_id: str | int, text: str, *, parse_mode: str | None = None) -> dict:
    settings = get_settings()
    token = settings.telegram_bot_token or ''
    if not token:
        return {'dry_run': True, 'chat_id': str(chat_id), 'text': text}

    payload = {'chat_id': chat_id, 'text': text, 'disable_web_page_preview': True}
    if parse_mode:
        payload['parse_mode'] = parse_mode

    url = f'https://api.telegram.org/bot{token}/sendMessage'
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(url, json=payload)
    return {'status_code': response.status_code, 'ok': response.is_success, 'body': response.text[:1000]}


async def handle_telegram_update(update: dict, db: AsyncSession) -> list[dict]:
    message = update.get('message') or update.get('edited_message')
    if not message:
        callback = update.get('callback_query')
        if callback:
            msg = callback.get('message') or {}
            chat_id = str((msg.get('chat') or {}).get('id') or '')
            text = '✅ Принято. Интерактивные обмены картами будут в следующем stage.'
            return [await send_telegram_message(chat_id, text)]
        return []

    text = message.get('text') or ''
    cmd, args = normalize_command(text)
    chat_id = _chat_id(message)
    ctype = _chat_type(message)
    profile = _from_profile(message)

    user = await get_or_create_user(db, platform='telegram', **profile)
    chat = await get_or_create_chat(
        db,
        platform='telegram',
        platform_chat_id=chat_id,
        title=_chat_title(message),
        chat_type=ctype,
    )

    if not cmd:
        return []

    if cmd == '/start':
        return [await send_telegram_message(chat_id, START_TEXT)]

    if cmd == '/help':
        return [await send_telegram_message(chat_id, HELP_TEXT)]

    if cmd == '/cards':
        hand, _deck = deal_classic()
        result = evaluate_five(hand)
        await add_score(
            db,
            user_id=user.id,
            platform='telegram',
            delta=result.points,
            scope='global',
            reason='cards',
            source='telegram_bot',
            meta={'hand': hand, 'combo': result.name},
        )
        if ctype != 'private':
            await add_score(
                db,
                user_id=user.id,
                platform='telegram',
                delta=result.points,
                scope='chat',
                chat_id=chat.id,
                reason='cards',
                source='telegram_bot',
                meta={'hand': hand, 'combo': result.name},
            )
        body = f"☠️ Твоя рука:\n{format_cards(hand)}\n\n{result.name} ({result.points} очков)\n{PHRASES[result.name]}"
        return [await send_telegram_message(chat_id, body)]

    if cmd == '/topscore':
        if ctype == 'private':
            items = await leaderboard(db, scope='global', limit=10)
            title = '🏆 Мировой топ игроков:'
        else:
            items = await leaderboard(db, scope='chat', chat_id=chat.id, limit=10)
            title = '🏆 Топ игроков в этом чате:'
        return [await send_telegram_message(chat_id, format_leaderboard(items, title))]

    if cmd == '/topduel':
        items = await leaderboard(db, scope='duel', chat_id=None if ctype == 'private' else chat.id, limit=10)
        return [await send_telegram_message(chat_id, format_leaderboard(items, '⚔️ Топ дуэлянтов:'))]

    if cmd == '/reset':
        settings = get_settings()
        boss_id = settings.boss_platform_user_id or ''
        if boss_id and profile['platform_user_id'] != boss_id:
            return [await send_telegram_message(chat_id, '⛔ Сброс доступен только владельцу.')]
        return [await send_telegram_message(chat_id, '🔄 Сброс через команды будет включён в админском stage. Сейчас используй admin API.')]

    if cmd == '/duel':
        if ctype == 'private':
            return [await send_telegram_message(chat_id, '⚠️ Дуэли доступны только в групповых чатах.')]
        target = args.strip()
        if not target:
            return [await send_telegram_message(chat_id, '⚠️ Используй команду так: /duel @никнейм')]
        target_username = target.lstrip('@').strip()
        if user.username and target_username.lower() == user.username.lower():
            return [await send_telegram_message(chat_id, '🪞 Себя на дуэль не вызывают. Это не храбрость, это зеркало.')]
        opponent = await db.scalar(select(User).where(User.username == target_username))
        if not opponent:
            return [await send_telegram_message(chat_id, '⚠️ Этого игрока пока нет в базе. Пусть сначала сыграет /cards.')]

        table, hand_a, hand_b, _deck = deal_holdem_duel()
        res_a = best_of_seven(table, hand_a)
        res_b = best_of_seven(table, hand_b)
        duel_score = score_duel(str(user.id), res_a, str(opponent.id), res_b)
        await add_score(db, user_id=user.id, platform='telegram', delta=duel_score.delta_a, scope='duel', chat_id=chat.id, reason='duel', source='telegram_bot')
        await add_score(db, user_id=opponent.id, platform='telegram', delta=duel_score.delta_b, scope='duel', chat_id=chat.id, reason='duel', source='telegram_bot')

        a_name = format_user_name(user.username, user.display_name, str(user.id))
        b_name = format_user_name(opponent.username, opponent.display_name, str(opponent.id))
        winner = 'ничья' if not duel_score.winner else (a_name if duel_score.winner == str(user.id) else b_name)
        body = (
            f"🎴 {a_name} и {b_name}, внимание на стол!\n\n"
            f"Карты на столе:\n{format_cards(table)}\n\n"
            f"🔷 {a_name}: {format_cards(hand_a)} — {res_a.name} ({duel_score.delta_a:+d})\n"
            f"🔶 {b_name}: {format_cards(hand_b)} — {res_b.name} ({duel_score.delta_b:+d})\n\n"
            f"🏆 Победитель: {winner}\n{duel_score.phrase}"
        )
        return [await send_telegram_message(chat_id, body)]

    return [await send_telegram_message(chat_id, HELP_TEXT)]
'''.strip() + '\n',

'app/api/webhooks.py': r'''
from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.bot.telegram import handle_telegram_update
from app.core.config import get_settings
from app.core.security import validate_shared_token
from app.db.base import get_db

router = APIRouter(prefix='/webhooks')


def _telegram_header_name() -> str:
    return 'x-telegram-' + 'bot-api-' + 'secret-token'


def _max_header_name() -> str:
    return 'x-max-' + 'bot-api-' + 'secret'


@router.post('/telegram')
async def telegram_webhook(request: Request, db: AsyncSession = Depends(get_db)):
    settings = get_settings()
    expected = settings.telegram_webhook_secret
    got = request.headers.get(_telegram_header_name()) or request.headers.get('x-webhook-token')
    if not validate_shared_token(got, expected):
        return {'ok': False, 'error': 'bad telegram webhook token'}
    update = await request.json()
    replies = await handle_telegram_update(update, db)
    return {'ok': True, 'platform': 'telegram', 'accepted': bool(update), 'replies': replies}


@router.post('/max')
async def max_webhook(request: Request):
    settings = get_settings()
    expected = settings.max_webhook_secret
    got = request.headers.get(_max_header_name()) or request.headers.get('x-webhook-token')
    if not validate_shared_token(got, expected):
        return {'ok': False, 'error': 'bad max webhook token'}
    update = await request.json()
    return {'ok': True, 'platform': 'max', 'accepted': bool(update), 'stage': 'max-adapter-next'}
'''.strip() + '\n',

'tests/test_bot_common.py': r'''
from app.bot.common import normalize_command


def test_normalize_plain_command():
    assert normalize_command('/cards') == ('/cards', '')


def test_normalize_command_with_bot_name_and_args():
    assert normalize_command('/duel@pokerrandom_bot @target') == ('/duel', '@target')
'''.strip() + '\n',
}

for path, content in files.items():
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')

print(f'WROTE {len(files)} files into {root}')
PY

python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"

git add .
git commit -m "Add Telegram command adapter stage 3" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

cd /opt/apps/poker-bot
TG_SECRET="$(grep '^TELEGRAM_WEBHOOK_SECRET=' .env | cut -d= -f2-)"

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s -H "X-Webhook-Token: $TG_SECRET" -H "Content-Type: application/json" --max-time 10 \
  -X POST http://10.8.0.1:8140/webhooks/telegram \
  -d '{"message":{"message_id":1,"from":{"id":1001,"is_bot":false,"first_name":"Smoke","username":"smoke_player"},"chat":{"id":1001,"type":"private","first_name":"Smoke"},"date":1,"text":"/cards"}}' && echo
curl -s -H "X-Webhook-Token: $TG_SECRET" -H "Content-Type: application/json" --max-time 10 \
  -X POST http://10.8.0.1:8140/webhooks/telegram \
  -d '{"message":{"message_id":2,"from":{"id":1001,"is_bot":false,"first_name":"Smoke","username":"smoke_player"},"chat":{"id":1001,"type":"private","first_name":"Smoke"},"date":1,"text":"/topscore"}}' && echo

echo "===== POKER BOT STAGE 3 DONE ====="
