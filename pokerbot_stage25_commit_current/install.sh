#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_stage25_commit_current_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER STAGE25 COMMIT CURRENT ====="
echo "log=$LOG"

# Do not reset. Stage24 already produced the repaired local tree; this stage only commits it correctly.
grep -q "Можно обменять от 0 до 5 карт" app/bot/telegram.py || { echo "REPAIRED_RULES_MISSING"; echo "POKER_STAGE25_FAIL"; exit 1; }
grep -q "topscore_global" app/bot/telegram.py || { echo "TOPS_MISSING"; echo "POKER_STAGE25_FAIL"; exit 1; }

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage25_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -80 /tmp/stage25_pycompile.log; echo POKER_STAGE25_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage25_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -120 /tmp/stage25_pytest.log; echo POKER_STAGE25_FAIL; exit 1; }
echo "PYTEST_OK"
tail -10 /tmp/stage25_pytest.log

git add -A
git status --short | sed -n '1,80p'
(git commit -m "Commit repaired poker core stage 25" || true)
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage25_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -80 /tmp/stage25_deploy.log; echo POKER_STAGE25_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -14 /tmp/stage25_deploy.log

./.venv/bin/python - <<'PY'
from app.bot.session_state import sessions
c = sessions._client()
keys = list(c.scan_iter(match='poker:session:*', count=500)) if c else []
if c and keys:
    c.delete(*keys)
print('SESSION_RESET=' + str(len(keys)))
PY

echo "===== STAGE25 RESULT ====="
git -C /opt/repos/poker-bot status --short
git -C /opt/repos/poker-bot log --oneline -3
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_STAGE25_COMMITTED_DONE"
