#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_stage24_finish_current_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER STAGE24 FINISH CURRENT ====="
echo "log=$LOG"

# Do not reset. Current working tree contains the repaired code from stage22/23.
grep -q "Можно обменять от 0 до 5 карт" app/bot/telegram.py || { echo "REPAIRED_CODE_MISSING"; echo "POKER_STAGE24_FAIL"; exit 1; }
grep -q "topscore_global" app/bot/telegram.py || { echo "TOP_CALLBACKS_MISSING"; echo "POKER_STAGE24_FAIL"; exit 1; }

cat > tests/test_stage11_select_cards.py <<'PY'
from app.bot.session_state import toggle_selected
from app.bot.telegram import classic_keyboard
from app.game.cards import display_card


def test_classic_keyboard_has_card_buttons():
    kb = classic_keyboard('s', ['♠A', '♥K', '♦Q', '♣J', '♠10'], {0})
    text = str(kb)
    assert '✅♤A' in text
    assert '♥️K' in text
    assert '♦️Q' in text
    assert '♧J' in text
    assert 'classic_done:s' in text


def test_display_card_adds_mobile_readable_suit_selector():
    assert display_card('♠A') == '♤A'
    assert display_card('♣10') == '♧10'
    assert display_card('♥K') == '♥️K'
    assert display_card('♦Q') == '♦️Q'


def test_duel_toggle_still_limits_two_by_core_rule():
    selected = set()
    assert toggle_selected(selected, 0)[0]
    assert toggle_selected(selected, 1)[0]
    ok, err = toggle_selected(selected, 2)
    assert not ok
    assert err
PY

cat > tests/test_suit_render_stage17.py <<'PY'
from app.game.cards import display_card, format_cards, parse_card
from app.bot.telegram import classic_keyboard


def test_display_card_uses_mobile_readable_suits():
    assert display_card('♥K') == '♥️K'
    assert display_card('♦A') == '♦️A'
    assert display_card('♣10') == '♧10'
    assert display_card('♠Q') == '♤Q'


def test_parse_card_accepts_rendered_suits():
    assert parse_card('♥️K')[:2] == ('♥', 'K')
    assert parse_card('♦️A')[:2] == ('♦', 'A')


def test_format_cards_uses_mobile_readable_suits():
    text = format_cards(['♥K', '♦A', '♣10', '♠Q'])
    assert '♥️K' in text
    assert '♦️A' in text
    assert '♧10' in text
    assert '♤Q' in text


def test_classic_keyboard_uses_rendered_suits():
    kb = classic_keyboard('sid', ['♥K', '♦A', '♣10', '♠Q', '♥2'], {0})
    text = str(kb)
    assert '✅♥️K' in text
    assert '▫️♦️A' in text
    assert '♧10' in text
    assert '♤Q' in text
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage24_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -80 /tmp/stage24_pycompile.log; echo POKER_STAGE24_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage24_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -120 /tmp/stage24_pytest.log; echo POKER_STAGE24_FAIL; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage24_pytest.log

git add app/game/cards.py app/bot/session_state.py app/bot/telegram.py tests/test_stage11_select_cards.py tests/test_suit_render_stage17.py tests/test_repair_stage22.py tests/test_core_clean_stage21.py tests/test_final_stage20.py tests/test_tg_ux_stage13.py tests/test_final_stage19.py 2>/dev/null || true
git commit -m "Finish poker repair current tree stage 24" || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage24_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage24_deploy.log; echo POKER_STAGE24_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -14 /tmp/stage24_deploy.log

./.venv/bin/python - <<'PY'
from app.bot.session_state import sessions
c = sessions._client()
keys = list(c.scan_iter(match='poker:session:*', count=500)) if c else []
if c and keys:
    c.delete(*keys)
print('SESSION_RESET=' + str(len(keys)))
PY

echo "===== STAGE24 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_STAGE24_DONE"
