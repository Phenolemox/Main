#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_suit_stage17_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER BOT SUIT RENDER STAGE17 ====="
echo "log=$LOG"

git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main
git reset --hard origin/main >/dev/null
git clean -fd >/dev/null

python3 - <<'PY'
from pathlib import Path
import re

root = Path('/opt/repos/poker-bot')
cards = root / 'app/game/cards.py'
tg = root / 'app/bot/telegram.py'

s = cards.read_text(encoding='utf-8')
if 'SUIT_RENDER' not in s:
    marker = "RANK_VALUE = {rank: idx + 2 for idx, rank in enumerate(RANKS)}\n"
    insert = '''RANK_VALUE = {rank: idx + 2 for idx, rank in enumerate(RANKS)}

SUIT_RENDER = {
    '\\u2660': '\\u2660\\ufe0f',
    '\\u2665': '\\u2665\\ufe0f',
    '\\u2666': '\\u2666\\ufe0f',
    '\\u2663': '\\u2663\\ufe0f',
}


def display_card(card: str) -> str:
    cleaned = (card or '').replace('\\ufe0f', '').strip()
    if not cleaned:
        return card
    suit = cleaned[0]
    rank = cleaned[1:]
    return f'{SUIT_RENDER.get(suit, suit)}{rank}'
'''
    s = s.replace(marker, insert, 1)

s = re.sub(
    r"def format_cards\(cards: list\[str\] \| tuple\[str, \.\.\.\]\) -> str:\n    return ' '\.join\(cards\)",
    "def format_cards(cards: list[str] | tuple[str, ...]) -> str:\n    return ' '.join(display_card(card) for card in cards)",
    s,
)
cards.write_text(s, encoding='utf-8')

s = tg.read_text(encoding='utf-8')
s = s.replace(
    'from app.game.cards import PHRASES, best_of_seven, evaluate_five, format_cards',
    'from app.game.cards import PHRASES, best_of_seven, display_card, evaluate_five, format_cards',
)
s = s.replace("f'{mark}{card}'", "f'{mark}{display_card(card)}'")
s = s.replace('f"{mark}{card}"', 'f"{mark}{display_card(card)}"')
tg.write_text(s, encoding='utf-8')

p = root / 'tests/test_stage11_select_cards.py'
if p.exists():
    t = p.read_text(encoding='utf-8')
    t = t.replace("assert '✅♠A' in text", "assert '\\u2705\\u2660\\ufe0fA' in text")
    p.write_text(t, encoding='utf-8')

(root / 'tests/test_suit_render_stage17.py').write_text('''from app.game.cards import display_card, format_cards, parse_card
from app.bot.telegram import classic_keyboard


def test_display_card_adds_emoji_variation_selector():
    assert display_card('\\u2665K') == '\\u2665\\ufe0fK'
    assert display_card('\\u2666A') == '\\u2666\\ufe0fA'
    assert display_card('\\u266310') == '\\u2663\\ufe0f10'
    assert display_card('\\u2660Q') == '\\u2660\\ufe0fQ'


def test_parse_card_accepts_rendered_suits():
    assert parse_card('\\u2665\\ufe0fK')[:2] == ('\\u2665', 'K')
    assert parse_card('\\u2666\\ufe0fA')[:2] == ('\\u2666', 'A')


def test_format_cards_uses_rendered_suits():
    text = format_cards(['\\u2665K', '\\u2666A', '\\u266310', '\\u2660Q'])
    assert '\\u2665\\ufe0fK' in text
    assert '\\u2666\\ufe0fA' in text
    assert '\\u2663\\ufe0f10' in text
    assert '\\u2660\\ufe0fQ' in text


def test_classic_keyboard_uses_rendered_suits():
    kb = classic_keyboard('sid', ['\\u2665K', '\\u2666A', '\\u266310', '\\u2660Q', '\\u26652'], {0})
    text = str(kb)
    assert '\\u2705\\u2665\\ufe0fK' in text
    assert '\\u25ab\\ufe0f\\u2666\\ufe0fA' in text
''', encoding='utf-8')

print('STAGE17_PATCHED_FILES=4')
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage17_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -40 /tmp/stage17_pycompile.log; echo POKER_SUIT_STAGE17_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage17_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -60 /tmp/stage17_pytest.log; echo POKER_SUIT_STAGE17_FAIL; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage17_pytest.log

git add app/game/cards.py app/bot/telegram.py tests/test_stage11_select_cards.py tests/test_suit_render_stage17.py
git commit -m 'Fix card suit rendering for Telegram clients stage 17' || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage17_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -60 /tmp/stage17_deploy.log; echo POKER_SUIT_STAGE17_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -18 /tmp/stage17_deploy.log

echo "===== STAGE17 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_SUIT_STAGE17_DONE"
