#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_stage15_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
echo "===== POKER TG RULES/UI STAGE15 ====="
echo "log=$LOG"

git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main
git pull --rebase origin main --quiet || true

python3 - <<'PY'
from pathlib import Path
import re

root = Path('/opt/repos/poker-bot')
ss = root / 'app/bot/session_state.py'
tg = root / 'app/bot/telegram.py'

s = ss.read_text(encoding='utf-8')
if 'mode: str = "open"' not in s:
    s = s.replace('    expires_at: float = 0.0\n    message_id: int | None = None', '    expires_at: float = 0.0\n    mode: str = "open"\n    message_id: int | None = None')
    s = s.replace('    data["expires_at"] = float(data["expires_at"])\n    if data.get("message_id") is not None:', '    data["expires_at"] = float(data["expires_at"])\n    data.setdefault("mode", "open")\n    if data.get("message_id") is not None:')
    s = s.replace('def start_duel(self, pending: PendingDuel) -> DuelSession:', 'def start_duel(self, pending: PendingDuel, mode: str = "open") -> DuelSession:')
    s = s.replace('            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},\n            expires_at=time.time() + DUEL_TTL_SECONDS,', '            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},\n            mode=mode,\n            expires_at=time.time() + DUEL_TTL_SECONDS,')
ss.write_text(s, encoding='utf-8')

s = tg.read_text(encoding='utf-8')
if 'from datetime import datetime, timedelta, timezone' not in s:
    s = s.replace('import re\n', 'import re\nfrom datetime import datetime, timedelta, timezone\n', 1)
if '_CLASSIC_ATTEMPT_FALLBACK' not in s:
    s = s.replace("NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')", "NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')\n_CLASSIC_ATTEMPT_FALLBACK: dict[str, tuple[int, float]] = {}")
s = s.replace("DUEL_HINT_GROUP = \"⚔️ Дуэль: /duel @ник. Вызов живёт 5 минут. Карты приходят участникам в личку.\"", "DUEL_HINT_GROUP = \"⚔️ Дуэль: /duel @ник. В вызове выбери режим: закрытая или открытая.\"")
s = s.replace("'🏆 Топ'", "'🏆 Топы'")

s = re.sub(r"def duel_request_keyboard\(duel_id: str\) -> dict:.*?\n\n\ndef duel_choice_keyboard", """def duel_request_keyboard(duel_id: str) -> dict:
    return {'inline_keyboard': [
        [
            {'text': '🔒 Закрытая', 'callback_data': f'duel_accept:{duel_id}:closed'},
            {'text': '👁 Открытая', 'callback_data': f'duel_accept:{duel_id}:open'},
        ],
        [{'text': '❌ Отказаться', 'callback_data': f'duel_decline:{duel_id}'}],
    ]}


def duel_choice_keyboard""", s, flags=re.S)

if 'def duel_open_keyboard' not in s:
    s = s.replace("""def result_keyboard(chat_type: str = 'private') -> dict:""", """def duel_open_keyboard(duel) -> dict:
    rows: list[list[dict]] = []
    rows.append([{'text': f"{'✅' if i in duel.selected[duel.challenger_user_id] else '▫️'}{card}", 'callback_data': f'duel_toggle:{duel.duel_id}:{duel.challenger_user_id}:{i}'} for i, card in enumerate(duel.hand_a)])
    rows.append([{'text': f"{'✅' if i in duel.selected[duel.opponent_user_id] else '▫️'}{card}", 'callback_data': f'duel_toggle:{duel.duel_id}:{duel.opponent_user_id}:{i}'} for i, card in enumerate(duel.hand_b)])
    rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel.duel_id}'}])
    return {'inline_keyboard': rows}


def result_keyboard(chat_type: str = 'private') -> dict:""", 1)

s = re.sub(r"def top_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef profile_keyboard", """def top_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🌍 Игра мир', 'callback_data': 'topscore_global'}, {'text': '🏠 Игра чат', 'callback_data': 'topscore_chat'}],
        [{'text': '🌍 Дуэли мир', 'callback_data': 'topduel_global'}, {'text': '🏠 Дуэли чат', 'callback_data': 'topduel_chat'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def profile_keyboard""", s, flags=re.S)

helpers = """
def _toggle_selected_limit(selected: set[int], index: int, limit: int) -> tuple[bool, str | None]:
    if index in selected:
        selected.remove(index)
        return True, None
    if len(selected) >= limit:
        return False, f'Можно выбрать максимум {limit} карт.'
    selected.add(index)
    return True, None


def _attempt_day_key(chat_type: str, chat_db_id: int, user_id: int) -> str:
    day = datetime.now(timezone.utc).strftime('%Y%m%d')
    scope = f'private:{user_id}' if chat_type == 'private' else f'chat:{chat_db_id}:{user_id}'
    return f'poker:limit:classic:{scope}:{day}'


def _attempt_ttl_seconds() -> int:
    now = datetime.now(timezone.utc)
    tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    return max(60, int((tomorrow - now).total_seconds()) + 3600)


def _consume_classic_attempt(chat_type: str, chat_db_id: int, user_id: int) -> tuple[bool, int, int]:
    limit = 5 if chat_type == 'private' else 1
    key = _attempt_day_key(chat_type, chat_db_id, user_id)
    ttl = _attempt_ttl_seconds()
    try:
        client = sessions._client()
    except Exception:
        client = None
    if client is not None:
        value = int(client.incr(key))
        if value == 1:
            client.expire(key, ttl)
        if value > limit:
            client.decr(key)
            return False, limit, limit
        return True, value, limit
    now = datetime.now(timezone.utc).timestamp()
    count, expires_at = _CLASSIC_ATTEMPT_FALLBACK.get(key, (0, now + ttl))
    if expires_at <= now:
        count, expires_at = 0, now + ttl
    if count >= limit:
        _CLASSIC_ATTEMPT_FALLBACK[key] = (count, expires_at)
        return False, count, limit
    count += 1
    _CLASSIC_ATTEMPT_FALLBACK[key] = (count, expires_at)
    return True, count, limit
"""
if 'def _toggle_selected_limit' not in s:
    s = s.replace('\n\nasync def send_telegram_message', helpers + '\n\nasync def send_telegram_message', 1)

s = re.sub(r"async def _start_classic\(chat_id: str, chat_type: str, chat_db_id: int, user: User\) -> dict:.*?\n\n\nasync def _finish_classic", """async def _start_classic(chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    if not await throttle.allow(f'cards:{chat_id}:{user.id}', 0.6):
        return {'ok': True, 'throttled': True}
    ok, used, limit = _consume_classic_attempt(chat_type, chat_db_id, user.id)
    if not ok:
        place = 'в личке с ботом' if chat_type == 'private' else 'в этом чате'
        return await send_telegram_message(chat_id, f'⛔ Лимит раздач на сегодня {place}: {used}/{limit}. Дуэли без лимита, но без дублей активных вызовов.', reply_markup=main_keyboard(chat_type))
    s = sessions.create_classic(chat_id=chat_id, chat_db_id=chat_db_id, user_id=user.id, chat_type=chat_type)
    text = f"☠️ Твоя рука:\\n{format_cards(s.hand)}\\n\\nМожно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.\\nПопытка: {used}/{limit}"
    return await send_telegram_message(chat_id, text, reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))


async def _finish_classic""", s, flags=re.S)

s = s.replace('ok, error = toggle_selected(s.selected, int(idx_s))', 'ok, error = _toggle_selected_limit(s.selected, int(idx_s), 5)')
s = s.replace('Выбери до 2 карт для обмена или жми 🎲 Играть.', 'Можно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.')
s = s.replace('Выбрано: {len(s.selected)}/2', 'Выбрано: {len(s.selected)}/5')

s = re.sub(r"async def _cmd_topscore\(.*?\n\n\nasync def _duel_help", """async def _cmd_tops(chat_id: str, chat_type: str) -> dict:
    return await send_telegram_message(chat_id, '🏆 Выбери рейтинг:', reply_markup=top_keyboard(chat_type))


async def _cmd_topscore(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, mode: str = 'auto') -> dict:
    if mode == 'global' or chat_type == 'private':
        items = await leaderboard(db, scope='global', limit=10)
        title = '🌍 Мировой топ обычных раздач:'
    else:
        items = await leaderboard(db, scope='chat', chat_id=chat_db_id, limit=10)
        title = '🏠 Топ обычных раздач в этом чате:'
    return await send_telegram_message(chat_id, format_leaderboard(items, title), reply_markup=top_keyboard(chat_type))


async def _cmd_topduel(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, mode: str = 'auto') -> dict:
    use_global = mode == 'global' or chat_type == 'private'
    items = await leaderboard(db, scope='duel', chat_id=None if use_global else chat_db_id, limit=10)
    title = '🌍 Мировой топ дуэлей:' if use_global else '🏠 Топ дуэлей в этом чате:'
    text = format_leaderboard(items, title) if items else title + '\\nПока пусто.'
    return await send_telegram_message(chat_id, text, reply_markup=top_keyboard(chat_type))


async def _duel_help""", s, flags=re.S)

s = re.sub(r"def _duel_status_text\(duel\) -> str:.*?\n\n\nasync def _send_duel_state", """def _duel_mode(duel) -> str:
    return str(getattr(duel, 'mode', 'open') or 'open')


def _duel_status_text(duel) -> str:
    ready_count = sum(1 for v in duel.ready.values() if v)
    a_ready = '✅' if duel.ready.get(duel.challenger_user_id) else '▫️'
    b_ready = '✅' if duel.ready.get(duel.opponent_user_id) else '▫️'
    if _duel_mode(duel) == 'closed':
        return f"🔒 Закрытая дуэль началась.\\nСтол: {format_cards(duel.table)}\\n\\n{a_ready} {duel.challenger_name}\\n{b_ready} {duel.opponent_name}\\n\\nКарты отправлены участникам в личку. Выберите до 2 карт и жмите 🎲 Готов.\\nГотовы: {ready_count}/2"
    return f"👁 Открытая дуэль.\\nСтол: {format_cards(duel.table)}\\n\\n{a_ready} {duel.challenger_name}: {format_cards(duel.hand_a)} — выбрано {len(duel.selected[duel.challenger_user_id])}/2\\n{b_ready} {duel.opponent_name}: {format_cards(duel.hand_b)} — выбрано {len(duel.selected[duel.opponent_user_id])}/2\\n\\nНажимай только свои карты. Потом 🎲 Готов.\\nГотовы: {ready_count}/2"


async def _send_duel_state""", s, flags=re.S)

s = re.sub(r"async def _send_duel_state\(chat_id: str, duel, message_id: int \| None = None\) -> dict:.*?\n\n\nasync def _telegram_private_chat_id", """async def _send_duel_state(chat_id: str, duel, message_id: int | None = None) -> dict:
    text = _duel_status_text(duel)
    reply_markup = duel_open_keyboard(duel) if _duel_mode(duel) == 'open' else None
    if message_id:
        return await edit_telegram_message(chat_id, message_id, text, reply_markup=reply_markup)
    return await send_telegram_message(chat_id, text, reply_markup=reply_markup)


async def _telegram_private_chat_id""", s, flags=re.S)

callback_block = """async def _callback(update: dict, db: AsyncSession) -> list[dict] | None:
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
        ok, error = _toggle_selected_limit(s.selected, int(idx_s), 5)
        sessions.save_classic(s)
        await answer_callback_query(cb_id, error or 'Выбрано', alert=bool(error))
        await edit_telegram_message(chat_id, message_id, f"☠️ Твоя рука:\\n{format_cards(s.hand)}\\n\\nМожно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.\\nВыбрано: {len(s.selected)}/5", reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))
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
        parts = data.split(':')
        did = parts[1]
        mode = parts[2] if len(parts) > 2 and parts[2] in {'open', 'closed'} else 'open'
        p = sessions.get_pending_duel(did)
        if not p:
            await answer_callback_query(cb_id, 'Вызов устарел.', alert=True)
            return []
        if p.opponent_user_id != user.id:
            await answer_callback_query(cb_id, 'Это не твой вызов.', alert=True)
            return []
        p = sessions.pop_pending_duel(did)
        d = sessions.start_duel(p, mode=mode)
        d.mode = mode
        d.message_id = message_id
        sessions.save_duel(d)
        await answer_callback_query(cb_id, 'Принято')
        await _send_duel_state(chat_id, d, message_id)
        if mode == 'closed':
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
        parts = data.split(':')
        did = parts[1]
        if len(parts) == 4:
            target_user_id = int(parts[2])
            idx = int(parts[3])
            if target_user_id != user.id:
                await answer_callback_query(cb_id, 'Это не твои карты.', alert=True)
                return []
        else:
            idx = int(parts[2])
        d = sessions.get_duel(did)
        if not d or user.id not in {d.challenger_user_id, d.opponent_user_id}:
            await answer_callback_query(cb_id, 'Это не твоя дуэль.', alert=True)
            return []
        if d.ready.get(user.id):
            await answer_callback_query(cb_id, 'Ты уже готов.', alert=True)
            return []
        ok, error = toggle_selected(d.selected[user.id], idx)
        sessions.save_duel(d)
        await answer_callback_query(cb_id, error or 'Выбрано', alert=bool(error))
        if _duel_mode(d) == 'closed':
            await _send_duel_private_cards(db, d, user.id, chat_id=chat_id, message_id=message_id)
        else:
            await _send_duel_state(d.chat_id, d, getattr(d, 'message_id', None))
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
        if _duel_mode(d) == 'closed':
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


"""
s = re.sub(r"async def _callback\(update: dict, db: AsyncSession\) -> list\[dict\] \| None:.*?\n\n\nasync def handle_telegram_update", callback_block + "async def handle_telegram_update", s, flags=re.S)

s = s.replace("if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id)]", "if cmd in {'/tops', '/top', '/rating', '/ratings'}:\n        return [await _cmd_tops(chat_id, ctype)]\n    if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'auto')]\n    if cmd == '/topscore_global':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'global')]\n    if cmd == '/topscore_chat':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'chat')]")
s = s.replace("if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id)]", "if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'auto')]\n    if cmd == '/topduel_global':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'global')]\n    if cmd == '/topduel_chat':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'chat')]")
s = s.replace("f'⚔️ {d.challenger_name} вызывает {d.opponent_name}.\\n5 минут на ответ.'", "f'⚔️ {d.challenger_name} вызывает {d.opponent_name}.\\n5 минут на ответ.\\n\\nВыберите режим:'")

tg.write_text(s, encoding='utf-8')

(root / 'tests/test_tg_rules_stage15.py').write_text(r"""
from app.bot.session_state import DuelSession
from app.bot.telegram import _toggle_selected_limit, duel_open_keyboard, duel_request_keyboard, top_keyboard, _duel_status_text


def test_classic_can_select_all_five_cards():
    selected = set()
    for idx in range(5):
        ok, err = _toggle_selected_limit(selected, idx, 5)
        assert ok
        assert err is None
    assert selected == {0, 1, 2, 3, 4}


def test_duel_request_has_open_and_closed_modes():
    flat = [btn['callback_data'] for row in duel_request_keyboard('did')['inline_keyboard'] for btn in row]
    assert 'duel_accept:did:closed' in flat
    assert 'duel_accept:did:open' in flat
    assert 'duel_decline:did' in flat


def test_top_keyboard_has_world_and_chat_for_game_and_duels():
    flat = [btn['callback_data'] for row in top_keyboard('group')['inline_keyboard'] for btn in row]
    assert {'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'} <= set(flat)


def test_open_duel_keyboard_marks_each_players_cards():
    d = DuelSession('d', 'c', 1, 10, 20, 'A', 'B', ['A'], ['2', '3'], ['4', '5'], [], {10: {1}, 20: set()}, {10: False, 20: False}, 9999999999, mode='open', message_id=7)
    flat = [btn['callback_data'] for row in duel_open_keyboard(d)['inline_keyboard'] for btn in row]
    assert 'duel_toggle:d:10:0' in flat
    assert 'duel_toggle:d:20:1' in flat
    assert 'duel_done:d' in flat


def test_duel_status_text_open_shows_hands_and_ready_count():
    d = DuelSession('d', 'c', 1, 10, 20, 'A', 'B', ['A'], ['2', '3'], ['4', '5'], [], {10: set(), 20: set()}, {10: True, 20: False}, 9999999999, mode='open', message_id=7)
    text = _duel_status_text(d)
    assert 'Открытая дуэль' in text
    assert 'Готовы: 1/2' in text
""".strip() + "\n", encoding='utf-8')
print('STAGE15_PATCHED_FILES=3')
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage15_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -40 /tmp/stage15_pycompile.log; echo "POKER_TG_RULES_STAGE15_FAIL"; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage15_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -60 /tmp/stage15_pytest.log; echo "POKER_TG_RULES_STAGE15_FAIL"; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage15_pytest.log

git add app/bot/telegram.py app/bot/session_state.py tests/test_tg_rules_stage15.py
git commit -m 'Fix Telegram rules and duel modes stage 15' || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage15_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -60 /tmp/stage15_deploy.log; echo "POKER_TG_RULES_STAGE15_FAIL"; exit 1; }
echo "DEPLOY_OK"
tail -18 /tmp/stage15_deploy.log

echo "===== STAGE15 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_TG_RULES_STAGE15_DONE"
