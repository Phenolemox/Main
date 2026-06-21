#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_repair_stage22_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER REPAIR STAGE22 ====="
echo "log=$LOG"
git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main

python3 - <<'PY'
from pathlib import Path
import re

root = Path('/opt/repos/poker-bot')

# readable suits for dark Telegram mobile: black suits use white variants
cards = root / 'app/game/cards.py'
s = cards.read_text(encoding='utf-8')
s = re.sub(
    r"SUIT_RENDER = \{.*?\}\n\n\ndef display_card",
    """SUIT_RENDER = {
    '♠': '♤',
    '♣': '♧',
    '♥': '♥️',
    '♦': '♦️',
}


def display_card""",
    s,
    flags=re.S,
)
cards.write_text(s, encoding='utf-8')

ss = root / 'app/bot/session_state.py'
s = ss.read_text(encoding='utf-8')
if 'mode: str = "open"' not in s:
    s = s.replace('    message_id: int | None = None\n', '    message_id: int | None = None\n    mode: str = "open"\n')
if 'data.setdefault("mode", "open")' not in s:
    s = s.replace('    if data.get("message_id") is not None:\n', '    data.setdefault("mode", "open")\n    if data.get("message_id") is not None:\n')
s = s.replace('def start_duel(self, pending: PendingDuel) -> DuelSession:', 'def start_duel(self, pending: PendingDuel, mode: str = "open") -> DuelSession:')
if '            mode=mode,' not in s:
    s = s.replace('            expires_at=time.time() + DUEL_TTL_SECONDS,\n', '            expires_at=time.time() + DUEL_TTL_SECONDS,\n            mode=mode,\n')
ss.write_text(s, encoding='utf-8')

tg = root / 'app/bot/telegram.py'
s = tg.read_text(encoding='utf-8')
if 'from datetime import datetime, timedelta, timezone' not in s:
    s = s.replace('import re\n', 'import re\nfrom datetime import datetime, timedelta, timezone\n', 1)

s = s.replace('/topscore — рейтинг игры\n/topduel — рейтинг дуэлей', '/tops — все рейтинги\n/topscore — обычная игра\n/topduel — дуэли')
s = s.replace('DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Вызов живёт 5 минут. Карты приходят участникам в личку."', 'DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Выбери закрытую или открытую игру."')

# unified menus
s = re.sub(r"def main_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef back_keyboard", """def main_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}],
        [{'text': '🏆 Топы', 'callback_data': 'tops'}, {'text': '👤 Профиль', 'callback_data': 'profile'}],
        [{'text': '📋 Помощь', 'callback_data': 'help'}],
    ]}


def back_keyboard""", s, flags=re.S)
s = re.sub(r"def result_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef top_keyboard", """def result_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топы', 'callback_data': 'tops'}],
        [{'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def top_keyboard""", s, flags=re.S)
s = re.sub(r"def top_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef profile_keyboard", """def top_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🌍 Игра мир', 'callback_data': 'topscore_global'}, {'text': '🏠 Игра чат', 'callback_data': 'topscore_chat'}],
        [{'text': '🌍 Дуэли мир', 'callback_data': 'topduel_global'}, {'text': '🏠 Дуэли чат', 'callback_data': 'topduel_chat'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def profile_keyboard""", s, flags=re.S)
s = re.sub(r"def profile_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef duel_menu_keyboard", """def profile_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топы', 'callback_data': 'tops'}],
    ]}


def duel_menu_keyboard""", s, flags=re.S)
s = re.sub(r"def duel_menu_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef _chat_type", """def duel_menu_keyboard(chat_type: str = 'private') -> dict:
    if chat_type == 'private':
        return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топы', 'callback_data': 'tops'}], [{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}
    return {'inline_keyboard': [[{'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}, {'text': '🏆 Топы', 'callback_data': 'tops'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def _chat_type""", s, flags=re.S)

# classic helper: no literal slash-n artefacts at runtime
helper = r'''def _classic_start_text(hand: list[str], used: int, limit: int) -> str:
    return "\n".join([
        "☠️ Твоя рука:",
        format_cards(hand),
        "",
        "Можно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.",
        f"Попытка: {used}/{limit}",
    ])


'''
if 'def _classic_start_text' not in s:
    s = s.replace('\n\nasync def _start_classic', '\n\n' + helper + 'async def _start_classic', 1)
else:
    s = re.sub(r"def _classic_start_text\(.*?\n\n\nasync def _start_classic", helper + 'async def _start_classic', s, flags=re.S)

start_classic = r'''async def _start_classic(chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    if not await throttle.allow(f'cards:{chat_id}:{user.id}', 0.6):
        return {'ok': True, 'throttled': True}
    ok, used, limit = _consume_classic_attempt(chat_type, chat_db_id, user.id)
    if not ok:
        place = 'в личке с ботом' if chat_type == 'private' else 'в этом чате'
        return await send_telegram_message(chat_id, f'⛔ Лимит раздач на сегодня {place}: {used}/{limit}. Дуэли без лимита.', reply_markup=main_keyboard(chat_type))
    game = sessions.create_classic(chat_id=chat_id, chat_db_id=chat_db_id, user_id=user.id, chat_type=chat_type)
    return await send_telegram_message(chat_id, _classic_start_text(game.hand, used, limit), reply_markup=classic_keyboard(game.session_id, game.hand, game.selected))
'''
s = re.sub(r"async def _start_classic\(chat_id: str, chat_type: str, chat_db_id: int, user: User\) -> dict:.*?\n\n\nasync def _finish_classic", start_classic + "\n\nasync def _finish_classic", s, flags=re.S)
s = s.replace('ok, error = toggle_selected(s.selected, int(idx_s))', 'ok, error = _toggle_selected_limit(s.selected, int(idx_s), 5)')
s = s.replace('Выбери до 2 карт для обмена или жми 🎲 Играть.', 'Можно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.')
s = s.replace('Выбрано: {len(s.selected)}/2', 'Выбрано: {len(s.selected)}/5')

# top commands with explicit modes
if 'async def _cmd_tops' not in s:
    s = s.replace('\n\nasync def _cmd_topscore', "\n\nasync def _cmd_tops(chat_id: str, chat_type: str) -> dict:\n    return await send_telegram_message(chat_id, '🏆 Выбери рейтинг:', reply_markup=top_keyboard(chat_type))\n\n\nasync def _cmd_topscore", 1)
s = re.sub(r"async def _cmd_topscore\(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int.*?\n\n\nasync def _cmd_topduel", """async def _cmd_topscore(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, mode: str = 'auto') -> dict:
    if mode == 'global' or chat_type == 'private':
        items = await leaderboard(db, scope='global', limit=10)
        title = '🌍 Мировой топ обычных раздач:'
    else:
        items = await leaderboard(db, scope='chat', chat_id=chat_db_id, limit=10)
        title = '🏠 Топ обычных раздач в этом чате:'
    return await send_telegram_message(chat_id, format_leaderboard(items, title), reply_markup=top_keyboard(chat_type))


async def _cmd_topduel""", s, flags=re.S)
s = re.sub(r"async def _cmd_topduel\(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int.*?\n\n\nasync def _duel_help", """async def _cmd_topduel(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, mode: str = 'auto') -> dict:
    use_global = mode == 'global' or chat_type == 'private'
    items = await leaderboard(db, scope='duel', chat_id=None if use_global else chat_db_id, limit=10)
    title = '🌍 Мировой топ дуэлей:' if use_global else '🏠 Топ дуэлей в этом чате:'
    text = format_leaderboard(items, title) if items else title + '\nПока пусто.'
    return await send_telegram_message(chat_id, text, reply_markup=top_keyboard(chat_type))


async def _duel_help""", s, flags=re.S)

# direct callback handling for top buttons
if 'TOP_CALLBACK_STAGE22' not in s:
    needle = "    cb_id = str(cb.get('id') or '')\n"
    insert = '''    # TOP_CALLBACK_STAGE22
    if data in {'tops', 'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'}:
        await answer_callback_query(cb_id, 'Принято')
        ctype = (chat.get('type') or 'private')
        chat_db = await get_or_create_chat(db, platform='telegram', platform_chat_id=chat_id, title=chat.get('title') or chat.get('first_name') or chat.get('username'), chat_type=ctype)
        if data == 'tops':
            return [await _cmd_tops(chat_id, ctype)]
        if data == 'topscore_global':
            return [await _cmd_topscore(db, chat_id, ctype, chat_db.id, 'global')]
        if data == 'topscore_chat':
            return [await _cmd_topscore(db, chat_id, ctype, chat_db.id, 'chat')]
        if data == 'topduel_global':
            return [await _cmd_topduel(db, chat_id, ctype, chat_db.id, 'global')]
        if data == 'topduel_chat':
            return [await _cmd_topduel(db, chat_id, ctype, chat_db.id, 'chat')]

'''
    s = s.replace(needle, needle + insert, 1)

s = s.replace("if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id)]", "if cmd in {'/tops', '/top', '/rating', '/ratings'}:\n        return [await _cmd_tops(chat_id, ctype)]\n    if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'auto')]")
s = s.replace("if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id)]", "if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'auto')]")

tg.write_text(s, encoding='utf-8')
print('REPAIR22_PATCH_OK')
PY

cat > tests/test_repair_stage22.py <<'PY'
from app.bot.telegram import _classic_start_text, _toggle_selected_limit, main_keyboard, result_keyboard, top_keyboard, duel_request_keyboard
from app.game.cards import display_card, format_cards


def flat(kb):
    return [b['callback_data'] for row in kb['inline_keyboard'] for b in row]


def test_classic_text_has_real_newlines_not_literal_backslash_n():
    text = _classic_start_text(['♠A', '♣10', '♥K', '♦Q', '♠2'], 1, 5)
    assert '\\n' not in text
    assert '\n' in text
    assert 'Можно обменять от 0 до 5 карт' in text


def test_black_suits_are_readable_on_dark_mobile():
    assert display_card('♠A').startswith('♤')
    assert display_card('♣10').startswith('♧')
    assert '♤A' in format_cards(['♠A'])
    assert '♧10' in format_cards(['♣10'])


def test_classic_allows_five_duel_modes_and_tops():
    selected = set()
    for i in range(5):
        ok, err = _toggle_selected_limit(selected, i, 5)
        assert ok and err is None
    assert {'tops', 'cards', 'duel_help'} <= set(flat(main_keyboard('private')))
    assert 'tops' in flat(result_keyboard('private'))
    assert {'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'} <= set(flat(top_keyboard('group')))
    assert {'duel_accept:x:closed', 'duel_accept:x:open'} <= set(flat(duel_request_keyboard('x')))
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage22_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -80 /tmp/stage22_pycompile.log; echo POKER_REPAIR_STAGE22_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage22_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -120 /tmp/stage22_pytest.log; echo POKER_REPAIR_STAGE22_FAIL; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage22_pytest.log

git add app/game/cards.py app/bot/session_state.py app/bot/telegram.py tests/test_repair_stage22.py
git commit -m "Repair Telegram card readability and top menu stage 22" || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage22_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage22_deploy.log; echo POKER_REPAIR_STAGE22_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -14 /tmp/stage22_deploy.log

./.venv/bin/python - <<'PY'
from app.bot.session_state import sessions
c=sessions._client()
ks=list(c.scan_iter(match='poker:session:*', count=500)) if c else []
if c and ks:
    c.delete(*ks)
print('SESSION_RESET=' + str(len(ks)))
PY

echo "===== STAGE22 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_REPAIR_STAGE22_DONE"
