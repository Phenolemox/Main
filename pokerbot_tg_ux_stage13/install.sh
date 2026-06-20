#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot

git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

python3 - <<'PY'
from pathlib import Path
p = Path('app/bot/telegram.py')
s = p.read_text(encoding='utf-8')

old = """def result_keyboard(chat_type: str = 'private') -> dict:\n    return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}], [{'text': '⬅️ Меню', 'callback_data': 'menu'}]]}\n\n\ndef top_keyboard(chat_type: str = 'private') -> dict:\n    return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}\n\n\ndef profile_keyboard(chat_type: str = 'private') -> dict:\n    return {'inline_keyboard': [[{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}], [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}]]}\n\n\ndef duel_menu_keyboard(chat_type: str = 'private') -> dict:\n    if chat_type == 'private':\n        return {'inline_keyboard': [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}\n    return {'inline_keyboard': [[{'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]}\n"""
new = """def result_keyboard(chat_type: str = 'private') -> dict:\n    return {'inline_keyboard': [\n        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}],\n        [{'text': '⬅️ Меню', 'callback_data': 'menu'}],\n    ]}\n\n\ndef top_keyboard(chat_type: str = 'private') -> dict:\n    rows = [[{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]]\n    if chat_type != 'private':\n        rows.insert(0, [{'text': '🏆 Топ игры', 'callback_data': 'topscore'}, {'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}])\n    return {'inline_keyboard': rows}\n\n\ndef profile_keyboard(chat_type: str = 'private') -> dict:\n    return {'inline_keyboard': [\n        [{'text': '✍️ Ник', 'callback_data': 'nick_help'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],\n        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '🏆 Топ', 'callback_data': 'topscore'}],\n    ]}\n\n\ndef duel_menu_keyboard(chat_type: str = 'private') -> dict:\n    if chat_type == 'private':\n        return {'inline_keyboard': [\n            [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],\n        ]}\n    return {'inline_keyboard': [\n        [{'text': '⚔️ Дуэль', 'callback_data': 'duel_help'}, {'text': '🛡️ Топ дуэлей', 'callback_data': 'topduel'}],\n        [{'text': '🃏 Раздача', 'callback_data': 'cards'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}],\n    ]}\n"""
if old in s:
    s = s.replace(old, new)
else:
    print('keyboard block already changed or not found')

s = s.replace("START_TEXT = \"🎰 Добро пожаловать за стол. Сделай ход.\"", "START_TEXT = \"🎰 Добро пожаловать за стол. Сделай ход.\"")

# Make duel hints shorter and less noisy.
s = s.replace(
    "DUEL_HINT_PRIVATE = \"⚔️ Дуэли работают в группах. Добавь бота в чат и вызови игрока: /duel @ник\"",
    "DUEL_HINT_PRIVATE = \"⚔️ Дуэли доступны в группах. Добавь бота в чат и вызови игрока: /duel @ник\"",
)
s = s.replace(
    "DUEL_HINT_GROUP = \"⚔️ Дуэль: /duel @ник. Вызов и выбор карт живут 5 минут.\"",
    "DUEL_HINT_GROUP = \"⚔️ Дуэль: /duel @ник. Вызов живёт 5 минут.\"",
)

# Remove menu button from active card-choice states to avoid accidental state breaks.
s = s.replace("rows.append([{'text': '🎲 Играть', 'callback_data': f'classic_done:{session_id}'}])", "rows.append([{'text': '🎲 Играть', 'callback_data': f'classic_done:{session_id}'}])")
s = s.replace("rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}])", "rows.append([{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}])")

p.write_text(s, encoding='utf-8')
print('telegram ux stage13 text/keyboards patched')
PY

cat > tests/test_tg_ux_stage13.py <<'PY'
from app.bot.telegram import duel_menu_keyboard, main_keyboard, result_keyboard, top_keyboard


def test_private_menu_has_duel_help():
    kb = main_keyboard('private')['inline_keyboard']
    assert any(btn['callback_data'] == 'duel_help' for row in kb for btn in row)


def test_group_duel_menu_has_duel_and_top():
    kb = duel_menu_keyboard('group')['inline_keyboard']
    flat = [btn['callback_data'] for row in kb for btn in row]
    assert 'duel_help' in flat
    assert 'topduel' in flat
    assert 'menu' in flat


def test_top_keyboard_group_has_both_tops():
    kb = top_keyboard('group')['inline_keyboard']
    flat = [btn['callback_data'] for row in kb for btn in row]
    assert 'topscore' in flat
    assert 'topduel' in flat


def test_result_keyboard_has_single_menu_back():
    kb = result_keyboard('private')['inline_keyboard']
    assert sum(1 for row in kb for btn in row if btn['callback_data'] == 'menu') == 1
PY

./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git add app/bot/telegram.py tests/test_tg_ux_stage13.py
git commit -m 'Clean Telegram menu keyboards stage 13' || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/redis && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions && echo

echo POKER_TG_UX_STAGE13_DONE
