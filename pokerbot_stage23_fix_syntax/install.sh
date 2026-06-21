#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_stage23_fix_syntax_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER STAGE23 FIX SYNTAX ====="
echo "log=$LOG"

python3 - <<'PY'
from pathlib import Path
p = Path('app/bot/telegram.py')
s = p.read_text(encoding='utf-8')
bad = "text = format_leaderboard(items, title) if items else title + '\nПока пусто.'"
good = "text = format_leaderboard(items, title) if items else title + '\\nПока пусто.'"
s = s.replace(bad, good)
s = s.replace("title + '\nПока пусто.'", "title + '\\nПока пусто.'")
s = s.replace("title + '\r\nПока пусто.'", "title + '\\nПока пусто.'")
p.write_text(s, encoding='utf-8')
print('SYNTAX_STRING_REPAIR_OK')
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage23_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -80 /tmp/stage23_pycompile.log; echo POKER_STAGE23_FIX_FAIL; exit 1; }
echo "PY_COMPILE_OK"

./.venv/bin/python -m pytest -q >/tmp/stage23_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -120 /tmp/stage23_pytest.log; echo POKER_STAGE23_FIX_FAIL; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage23_pytest.log

git add app/game/cards.py app/bot/session_state.py app/bot/telegram.py tests/test_repair_stage22.py tests/test_core_clean_stage21.py tests/test_final_stage20.py tests/test_tg_ux_stage13.py tests/test_final_stage19.py 2>/dev/null || true
git commit -m "Fix Telegram top menu syntax stage 23" || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage23_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage23_deploy.log; echo POKER_STAGE23_FIX_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -14 /tmp/stage23_deploy.log

./.venv/bin/python - <<'PY'
from app.bot.session_state import sessions
c = sessions._client()
keys = list(c.scan_iter(match='poker:session:*', count=500)) if c else []
if c and keys:
    c.delete(*keys)
print('SESSION_RESET=' + str(len(keys)))
PY

echo "===== STAGE23 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_STAGE23_FIX_DONE"
