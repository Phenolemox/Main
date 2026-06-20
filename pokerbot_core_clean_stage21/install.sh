#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_core_clean_stage21_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER CORE CLEAN STAGE21 ====="
echo "log=$LOG"

git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main
# do not reset: keep current repaired code as base

python3 - <<'PY'
from pathlib import Path
import re
p = Path('app/bot/telegram.py')
s = p.read_text(encoding='utf-8')

s = s.replace('/topscore — рейтинг игры\n/topduel — рейтинг дуэлей', '/tops — все рейтинги\n/topscore — обычная игра\n/topduel — дуэли')
s = s.replace('DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Вызов живёт 5 минут. Карты приходят участникам в личку."', 'DUEL_HINT_GROUP = "⚔️ Дуэль: /duel @ник. Выбери закрытую или открытую игру."')

start_classic = '''async def _start_classic(chat_id: str, chat_type: str, chat_db_id: int, user: User) -> dict:
    if not await throttle.allow(f'cards:{chat_id}:{user.id}', 0.6):
        return {'ok': True, 'throttled': True}
    ok, used, limit = _consume_classic_attempt(chat_type, chat_db_id, user.id)
    if not ok:
        place = 'в личке с ботом' if chat_type == 'private' else 'в этом чате'
        return await send_telegram_message(chat_id, f'⛔ Лимит раздач на сегодня {place}: {used}/{limit}. Дуэли без лимита.', reply_markup=main_keyboard(chat_type))
    s = sessions.create_classic(chat_id=chat_id, chat_db_id=chat_db_id, user_id=user.id, chat_type=chat_type)
    text = (
        "☠️ Твоя рука:\n"
        f"{format_cards(s.hand)}\n\n"
        "Можно обменять от 0 до 5 карт. Нажимай карты и жми 🎲 Играть.\n"
        f"Попытка: {used}/{limit}"
    )
    return await send_telegram_message(chat_id, text, reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))
'''
s = re.sub(r"async def _start_classic\(chat_id: str, chat_type: str, chat_db_id: int, user: User\) -> dict:.*?\n\n\nasync def _finish_classic", start_classic + "\n\nasync def _finish_classic", s, flags=re.S)

if 'CORE_TOP_CALLBACK_STAGE21' not in s:
    needle = "    cb_id = str(cb.get('id') or '')\n"
    insert = '''    # CORE_TOP_CALLBACK_STAGE21
    if data in {'tops', 'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'}:
        await answer_callback_query(cb_id, 'Принято')
        ctype = (chat.get('type') or 'private')
        chat_db = await get_or_create_chat(
            db,
            platform='telegram',
            platform_chat_id=chat_id,
            title=chat.get('title') or chat.get('first_name') or chat.get('username'),
            chat_type=ctype,
        )
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

if 'async def _cmd_tops' not in s:
    s = s.replace("\n\nasync def _cmd_topscore", "\n\nasync def _cmd_tops(chat_id: str, chat_type: str) -> dict:\n    return await send_telegram_message(chat_id, '🏆 Выбери рейтинг:', reply_markup=top_keyboard(chat_type))\n\n\nasync def _cmd_topscore", 1)

# route text commands to top menu/buttons
s = s.replace("if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id)]", "if cmd in {'/tops', '/top', '/rating', '/ratings'}:\n        return [await _cmd_tops(chat_id, ctype)]\n    if cmd == '/topscore':\n        return [await _cmd_topscore(db, chat_id, ctype, chat.id, 'auto')]")
s = s.replace("if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id)]", "if cmd == '/topduel':\n        return [await _cmd_topduel(db, chat_id, ctype, chat.id, 'auto')]")

# final sanity: visible text must not contain escaped newline markers in card start text
if "\\n{format_cards" in s or 'Твоя рука:\\n' in s and 'text = (' not in s:
    raise SystemExit('BAD_ESCAPED_NEWLINE_IN_START_CLASSIC')

p.write_text(s, encoding='utf-8')
print('CORE_PATCH_OK')
PY

cat > tests/test_core_clean_stage21.py <<'PY'
from app.bot.telegram import main_keyboard, result_keyboard, top_keyboard, _toggle_selected_limit


def flat(kb):
    return [b['callback_data'] for row in kb['inline_keyboard'] for b in row]


def test_menus_have_tops():
    assert 'tops' in flat(main_keyboard('private'))
    assert 'tops' in flat(result_keyboard('private'))


def test_top_keyboard_has_four_top_modes():
    data = set(flat(top_keyboard('group')))
    assert {'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'} <= data


def test_classic_limit_helper_allows_five():
    selected = set()
    for i in range(5):
        ok, err = _toggle_selected_limit(selected, i, 5)
        assert ok and err is None
    assert selected == {0,1,2,3,4}
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage21_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -80 /tmp/stage21_pycompile.log; echo POKER_CORE_CLEAN_STAGE21_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage21_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -120 /tmp/stage21_pytest.log; echo POKER_CORE_CLEAN_STAGE21_FAIL; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage21_pytest.log

git add app/bot/telegram.py tests/test_core_clean_stage21.py
git commit -m "Clean poker core menu and card UX stage 21" || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage21_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage21_deploy.log; echo POKER_CORE_CLEAN_STAGE21_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -14 /tmp/stage21_deploy.log

echo "===== STAGE21 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_CORE_CLEAN_STAGE21_DONE"
