from pathlib import Path
import re

root = Path('/opt/repos/poker-bot')
ss = root / 'app/bot/session_state.py'
tg = root / 'app/bot/telegram.py'

s = ss.read_text(encoding='utf-8')
if 'mode: str = "open"' not in s:
    s = s.replace('    ready: dict[int, bool] = field(default_factory=dict)\n    expires_at: float = 0.0', '    ready: dict[int, bool] = field(default_factory=dict)\n    mode: str = "open"\n    expires_at: float = 0.0')
if 'data.setdefault("mode", "open")' not in s:
    s = s.replace('    data["expires_at"] = float(data["expires_at"])\n    return DuelSession(**data)', '    data["expires_at"] = float(data["expires_at"])\n    data.setdefault("mode", "open")\n    return DuelSession(**data)')
    s = s.replace('    data["expires_at"] = float(data["expires_at"])\n    if data.get("message_id") is not None:', '    data["expires_at"] = float(data["expires_at"])\n    data.setdefault("mode", "open")\n    if data.get("message_id") is not None:')
s = s.replace('def start_duel(self, pending: PendingDuel) -> DuelSession:', 'def start_duel(self, pending: PendingDuel, mode: str = "open") -> DuelSession:')
if '            mode=mode,' not in s:
    s = s.replace('            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},\n            expires_at=time.time() + DUEL_TTL_SECONDS,', '            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},\n            mode=mode,\n            expires_at=time.time() + DUEL_TTL_SECONDS,')
ss.write_text(s, encoding='utf-8')

s = tg.read_text(encoding='utf-8')
if 'from datetime import datetime, timedelta, timezone' not in s:
    s = s.replace('import re\n', 'import re\nfrom datetime import datetime, timedelta, timezone\n', 1)
if '_CLASSIC_ATTEMPT_FALLBACK' not in s:
    s = s.replace("NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')", "NICK_RE = re.compile(r'^[A-Za-zА-Яа-яЁё0-9 _.-]{2,24}$')\n_CLASSIC_ATTEMPT_FALLBACK: dict[str, tuple[int, float]] = {}")

def sub(pat: str, repl: str):
    global s
    s = re.sub(pat, repl, s, flags=re.S)

sub(r"def main_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef back_keyboard", """def main_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}],
        [{'text': '🏆 Топы', 'callback_data': 'tops'}, {'text': '👤 Профиль', 'callback_data': 'profile'}],
        [{'text': '📋 Помощь', 'callback_data': 'help'}],
    ]}


def back_keyboard""")

sub(r"def duel_request_keyboard\(duel_id: str\) -> dict:.*?\n\n\ndef duel_choice_keyboard", """def duel_request_keyboard(duel_id: str) -> dict:
    return {'inline_keyboard': [
        [{'text': '🔒 Закрытая', 'callback_data': f'duel_accept:{duel_id}:closed'}, {'text': '👁 Открытая', 'callback_data': f'duel_accept:{duel_id}:open'}],
        [{'text': '❌ Отказаться', 'callback_data': f'duel_decline:{duel_id}'}],
    ]}


def duel_choice_keyboard""")

if 'def duel_open_keyboard' not in s:
    s = s.replace("def result_keyboard(chat_type: str = 'private') -> dict:", """def duel_open_keyboard(duel) -> dict:
    rows: list[list[dict]] = []
    rows.append([{'text': f\"{'✅' if i in duel.selected[duel.challenger_user_id] else '▫️'}{display_card(card)}\", 'callback_data': f'duel_toggle:{duel.duel_id}:{duel.challenger_user_id}:{i}'} for i, card in enumerate(duel.hand_a)])
    rows.append([{'text': f\"{'✅' if i in duel.selected[duel.opponent_user_id] else '▫️'}{display_card(card)}\", 'callback_data': f'duel_toggle:{duel.duel_id}:{duel.opponent_user_id}:{i}'} for i, card in enumerate(duel.hand_b)])
    rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel.duel_id}'}])
    return {'inline_keyboard': rows}


def result_keyboard(chat_type: str = 'private') -> dict:""", 1)

sub(r"def result_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef top_keyboard", """def result_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топы', 'callback_data': 'tops'}],
        [{'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def top_keyboard""")

sub(r"def top_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef profile_keyboard", """def top_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '🌍 Игра мир', 'callback_data': 'topscore_global'}, {'text': '🏠 Игра чат', 'callback_data': 'topscore_chat'}],
        [{'text': '🌍 Дуэли мир', 'callback_data': 'topduel_global'}, {'text': '🏠 Дуэли чат', 'callback_data': 'topduel_chat'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
    ]}


def profile_keyboard""")

sub(r"def profile_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef duel_menu_keyboard", """def profile_keyboard(chat_type: str = 'private') -> dict:
    return {'inline_keyboard': [
        [{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],
        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топы', 'callback_data': 'tops'}],
    ]}


def duel_menu_keyboard""")

sub(r"def duel_menu_keyboard\(chat_type: str = 'private'\) -> dict:.*?\n\n\ndef _chat_type", """def duel_menu_keyboard(chat_type: str = 'private') -> dict:
    if chat_type == 'private':
        return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топы', 'callback_data': 'tops'}], [{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}
    return {'inline_keyboard': [[{'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}, {'text': '🏆 Топы', 'callback_data': 'tops'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}


def _chat_type""")

helpers = """
def _toggle_selected_limit(selected: set[int], index: int, limit: int) -> tuple[bool, str | None]:
    if index in selected:
        selected.remove(index)
        return True, None
    if len(selected) >= limit:
        return False, f'Можно выбрать максимум {limit} карт.'
    selected.add(index)
    return True, None


def _consume_classic_attempt(chat_type: str, chat_db_id: int, user_id: int) -> tuple[bool, int, int]:
    limit = 5 if chat_type == 'private' else 1
    day = datetime.now(timezone.utc).strftime('%Y%m%d')
    scope = f'private:{user_id}' if chat_type == 'private' else f'chat:{chat_db_id}:{user_id}'
    key = f'poker:limit:classic:{scope}:{day}'
    try:
        client = sessions._client()
    except Exception:
        client = None
    if client is not None:
        value = int(client.incr(key))
        if value == 1:
            tomorrow = (datetime.now(timezone.utc) + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
            client.expire(key, max(60, int((tomorrow - datetime.now(timezone.utc)).total_seconds()) + 3600))
        if value > limit:
            client.decr(key)
            return False, limit, limit
        return True, value, limit
    return True, 1, limit
"""
if 'def _toggle_selected_limit' not in s:
    s = s.replace('\n\nasync def send_telegram_message', helpers + '\n\nasync def send_telegram_message', 1)

sub(r"async def _start_classic\(chat_id: str, chat_type: str, chat_db_id: int, user: User\) -> dict:.*?\n\n\nasync def _finish_classic", """async def _start_classic(chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    if not await throttle.allow(f'cards:{chat_id}:{user.id}', 0.6):
        return {'ok': True, 'throttled': True}
    ok, used, limit = _consume_classic_attempt(chat_type, chat_db_id, user.id)
    if not ok:
        place = 'в личке с ботом' if chat_type == 'private' else 'в этом чате'
        return await send_telegram_message(chat_id, f'⛔ Лимит раздач на сегодня {place}: {used}/{limit}. Дуэли без лимита.', reply_markup=main_keyboard(chat_type))
    s = sessions.create_classic(chat_id=chat_id, chat_db_id=chat_db_id, user_id=user.id, chat_type=chat_type)
    text = f\"☠️ Твоя рука:\\n{format_cards(s.hand)}\\n\\nМожно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.\\nПопытка: {used}/{limit}\"
    return await send_telegram_message(chat_id, text, reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))


async def _finish_classic""")

s = s.replace('ok, error = toggle_selected(s.selected, int(idx_s))', 'ok, error = _toggle_selected_limit(s.selected, int(idx_s), 5)')
s = s.replace('Выбери до 2 карт для обмена или жми 🎲 Играть.', 'Можно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.')
s = s.replace('Выбрано: {len(s.selected)}/2', 'Выбрано: {len(s.selected)}/5')

if 'async def _cmd_tops' not in s:
    s = s.replace('\n\nasync def _cmd_topscore', "\n\nasync def _cmd_tops(chat_id: str, chat_type: str) -> dict:\n    return await send_telegram_message(chat_id, '🏆 Выбери рейтинг:', reply_markup=top_keyboard(chat_type))\n\n\nasync def _cmd_topscore", 1)

sub(r"async def _cmd_topscore\(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int\) -> dict:.*?\n\n\nasync def _cmd_topduel", """async def _cmd_topscore(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, mode: str = 'auto') -> dict:
    if mode == 'global' or chat_type == 'private':
        items = await leaderboard(db, scope='global', limit=10)
        title = '🌍 Мировой топ обычных раздач:'
    else:
        items = await leaderboard(db, scope='chat', chat_id=chat_db_id, limit=10)
        title = '🏠 Топ обычных раздач в этом чате:'
    return await send_telegram_message(chat_id, format_leaderboard(items, title), reply_markup=top_keyboard(chat_type))


async def _cmd_topduel""")

sub(r"async def _cmd_topduel\(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int\) -> dict:.*?\n\n\nasync def _duel_help", """async def _cmd_topduel(db: AsyncSession, chat_id: str, chat_type: str, chat_db_id: int, mode: str = 'auto') -> dict:
    use_global = mode == 'global' or chat_type == 'private'
    items = await leaderboard(db, scope='duel', chat_id=None if use_global else chat_db_id, limit=10)
    title = '🌍 Мировой топ дуэлей:' if use_global else '🏠 Топ дуэлей в этом чате:'
    text = format_leaderboard(items, title) if items else title + '\\nПока пусто.'
    return await send_telegram_message(chat_id, text, reply_markup=top_keyboard(chat_type))


async def _duel_help""")

s = s.replace("if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id)]", "if cmd in {'/tops', '/top', '/rating', '/ratings'}:\n        return [await _cmd_tops(chat_id, ctype)]\n    if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'auto')]\n    if cmd == '/topscore_global':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'global')]\n    if cmd == '/topscore_chat':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'chat')]")
s = s.replace("if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id)]", "if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'auto')]\n    if cmd == '/topduel_global':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'global')]\n    if cmd == '/topduel_chat':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'chat')]")

# Duel accept mode parsing: closed keeps private cards; open stays public.
sub(r"    if data.startswith\('duel_accept:'\):.*?\n\n    if data.startswith\('duel_decline:'\):", """    if data.startswith('duel_accept:'):
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

    if data.startswith('duel_decline:'):""")

tg.write_text(s, encoding='utf-8')
print('PATCH_RULES_OK')
