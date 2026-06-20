#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_finalize_stage20_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER FINALIZE STAGE20 ====="
echo "log=$LOG"

grep -q "Можно обменять от 0 до 5 карт" app/bot/telegram.py || { echo "LOCAL_RULES_PATCH_MISSING"; echo "POKER_FINALIZE_STAGE20_FAIL"; exit 1; }

cat > tests/test_tg_ux_stage13.py <<'PY'
from app.bot.telegram import duel_menu_keyboard, main_keyboard, result_keyboard, top_keyboard


def flat(kb):
    return [btn['callback_data'] for row in kb['inline_keyboard'] for btn in row]


def test_private_menu_has_cards_duel_tops_profile():
    data = flat(main_keyboard('private'))
    assert {'cards', 'duel_help', 'tops', 'profile', 'help'} <= set(data)


def test_group_duel_menu_has_duel_tops_cards_menu():
    data = flat(duel_menu_keyboard('group'))
    assert {'duel_help', 'tops', 'cards', 'menu'} <= set(data)


def test_top_keyboard_has_all_four_tops():
    data = flat(top_keyboard('group'))
    assert {'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'} <= set(data)


def test_result_keyboard_uses_tops():
    data = flat(result_keyboard('private'))
    assert 'tops' in data
    assert 'menu' in data
PY

cat > tests/test_final_stage20.py <<'PY'
from app.bot.telegram import _toggle_selected_limit, duel_request_keyboard, main_keyboard, top_keyboard


def flat(kb):
    return [btn['callback_data'] for row in kb['inline_keyboard'] for btn in row]


def test_classic_selects_five():
    selected = set()
    for i in range(5):
        ok, err = _toggle_selected_limit(selected, i, 5)
        assert ok and err is None
    assert selected == {0, 1, 2, 3, 4}


def test_main_menu_uses_tops_not_old_topscore():
    data = flat(main_keyboard('private'))
    assert 'tops' in data
    assert 'topscore' not in data


def test_top_modes_four_buttons():
    data = flat(top_keyboard('group'))
    assert {'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'} <= set(data)


def test_duel_modes():
    data = flat(duel_request_keyboard('x'))
    assert 'duel_accept:x:open' in data
    assert 'duel_accept:x:closed' in data
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage20_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -40 /tmp/stage20_pycompile.log; echo POKER_FINALIZE_STAGE20_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage20_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -80 /tmp/stage20_pytest.log; echo POKER_FINALIZE_STAGE20_FAIL; exit 1; }
echo "PYTEST_OK"
tail -10 /tmp/stage20_pytest.log

git add app/bot/telegram.py app/bot/session_state.py tests/test_tg_ux_stage13.py tests/test_final_stage20.py
git commit -m "Finalize poker rules repair stage 20" || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage20_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -60 /tmp/stage20_deploy.log; echo POKER_FINALIZE_STAGE20_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -14 /tmp/stage20_deploy.log

python3 - <<'PY'
from pathlib import Path
import redis
url=''
for p in [Path('/opt/apps/poker-bot/.env'), Path('/opt/repos/poker-bot/.env')]:
    if p.exists():
        for line in p.read_text(encoding='utf-8', errors='ignore').splitlines():
            if line.startswith('REDIS_URL=') or line.startswith('POKER_REDIS_URL='):
                url=line.split('=',1)[1].strip().strip('"').strip("'")
if url:
    r=redis.Redis.from_url(url, decode_responses=True)
    keys=list(r.scan_iter(match='poker:session:*', count=500))
    if keys:
        r.delete(*keys)
    print('SESSION_RESET='+str(len(keys)))
else:
    print('SESSION_RESET_SKIPPED')
PY

echo "===== STAGE20 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_FINALIZE_STAGE20_DONE"
