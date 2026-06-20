#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_final_stage19_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER FINAL STAGE19 ====="
echo "log=$LOG"

git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main
git reset --hard origin/main >/dev/null
git clean -fd >/dev/null

curl -fsSL https://raw.githubusercontent.com/Phenolemox/Main/main/pokerbot_final_stage19/patch_rules.py -o /tmp/poker_patch_rules.py
python3 /tmp/poker_patch_rules.py

cat > tests/test_final_stage19.py <<'PY'
from app.bot.telegram import _toggle_selected_limit, duel_request_keyboard, main_keyboard, top_keyboard


def test_classic_selects_five():
    selected = set()
    for i in range(5):
        ok, err = _toggle_selected_limit(selected, i, 5)
        assert ok and err is None
    assert selected == {0, 1, 2, 3, 4}


def test_main_menu_has_tops():
    flat = [btn['callback_data'] for row in main_keyboard('private')['inline_keyboard'] for btn in row]
    assert 'tops' in flat
    assert 'topscore' not in flat


def test_top_modes_four_buttons():
    flat = [btn['callback_data'] for row in top_keyboard('group')['inline_keyboard'] for btn in row]
    assert {'topscore_global', 'topscore_chat', 'topduel_global', 'topduel_chat'} <= set(flat)


def test_duel_modes():
    flat = [btn['callback_data'] for row in duel_request_keyboard('x')['inline_keyboard'] for btn in row]
    assert 'duel_accept:x:open' in flat
    assert 'duel_accept:x:closed' in flat
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage19_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -80 /tmp/stage19_pycompile.log; echo POKER_FINAL_STAGE19_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage19_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -120 /tmp/stage19_pytest.log; echo POKER_FINAL_STAGE19_FAIL; exit 1; }
echo "PYTEST_OK"
tail -15 /tmp/stage19_pytest.log

git add app/bot/telegram.py app/bot/session_state.py tests/test_final_stage19.py
git commit -m "Final Telegram rules menu fix stage 19" || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage19_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage19_deploy.log; echo POKER_FINAL_STAGE19_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -18 /tmp/stage19_deploy.log

python3 - <<'PY'
from pathlib import Path
import redis
url = ''
for p in [Path('/opt/apps/poker-bot/.env'), Path('/opt/repos/poker-bot/.env')]:
    if p.exists():
        for line in p.read_text(encoding='utf-8', errors='ignore').splitlines():
            if line.startswith('REDIS_URL=') or line.startswith('POKER_REDIS_URL='):
                url = line.split('=', 1)[1].strip().strip('"').strip("'")
if url:
    r = redis.Redis.from_url(url, decode_responses=True)
    keys = list(r.scan_iter(match='poker:session:*', count=500))
    if keys:
        r.delete(*keys)
    print('SESSION_RESET=' + str(len(keys)))
else:
    print('SESSION_RESET_SKIPPED')
PY

echo "===== STAGE19 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_FINAL_STAGE19_DONE"
