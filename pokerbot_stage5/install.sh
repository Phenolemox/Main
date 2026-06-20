#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="Phenolemox/poker-bot"
TARGET_DIR="/opt/repos/poker-bot"

if [ ! -d "$TARGET_DIR/.git" ]; then
  rm -rf "$TARGET_DIR"
  gh repo clone "$TARGET_REPO" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
git remote set-url origin "https://github.com/${TARGET_REPO}.git" 2>/dev/null || true
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

python3 - <<'PY'
from pathlib import Path

root = Path('/opt/repos/poker-bot')
main_py = root / 'app/main.py'
text = main_py.read_text(encoding='utf-8')
needle = "logging.basicConfig(level=logging.INFO)\nlog = logging.getLogger('poker_bot')\n"
patch = "logging.basicConfig(level=logging.INFO)\nlogging.getLogger('httpx').setLevel(logging.WARNING)\nlogging.getLogger('httpcore').setLevel(logging.WARNING)\nlog = logging.getLogger('poker_bot')\n"
if needle in text and patch not in text:
    text = text.replace(needle, patch)
main_py.write_text(text, encoding='utf-8')

poller = root / 'app/bot/telegram_poller.py'
text = poller.read_text(encoding='utf-8')
text = text.replace(
    "log.warning('telegram api %s http=%s body=%s', method, response.status_code, str(body)[:500])",
    "log.warning('telegram api %s http=%s description=%s', method, response.status_code, body.get('description'))",
)
poller.write_text(text, encoding='utf-8')

print('stage5 logging redaction patch applied')
PY

python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip >/dev/null
./.venv/bin/pip install -r requirements.txt >/dev/null
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"

git add .
git commit -m "Redact Telegram request logging stage 5" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

cd /opt/apps/poker-bot
python3 - <<'PY'
from pathlib import Path
import re

data = {}
for line in Path('.env').read_text(encoding='utf-8').splitlines():
    if '=' in line and not line.strip().startswith('#'):
        k, v = line.split('=', 1)
        data[k] = v

t = data.get('TELEGRAM_BOT_TOKEN', '')
print('TELEGRAM_BOT_TOKEN_LEN=', len(t))
print('TELEGRAM_BOT_TOKEN_FORMAT=', 'OK' if re.fullmatch(r'\d{8,12}:[A-Za-z0-9_-]{30,80}', t or '') else 'BAD')
print('TELEGRAM_POLLING_ENABLED=', data.get('TELEGRAM_POLLING_ENABLED', ''))
PY

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
ai-logs poker-bot 50 | grep -E "telegram polling|telegram api|ERROR|WARNING|health" || true

echo "===== POKER BOT STAGE 5 DONE ====="
