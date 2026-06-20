#!/usr/bin/env bash
set -euo pipefail

log(){ printf '\n===== %s =====\n' "$1"; }

DEVROOT="/opt/devtools"
PYVENV="$DEVROOT/python-qa"
BIN="$HOME/bin"

# /opt is root-owned on clean Ubuntu. Create root path with sudo, then hand this devtools subtree to admin.
mkdir -p "$BIN"
sudo mkdir -p "$DEVROOT" /opt/data/ai-control-room/server
sudo chown -R "$(whoami):$(id -gn)" "$DEVROOT"
sudo chown -R "$(whoami):$(id -gn)" /opt/data/ai-control-room/server

log "SERVER DEVTOOLS STAGE 1"
echo "host=$(hostname) user=$(whoami) time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "APT TOOLBOX"
sudo apt-get update -y
sudo apt-get install -y \
  jq ripgrep fd-find tree sqlite3 shellcheck yamllint htop ncdu unzip zip make curl git \
  python3-venv python3-pip nodejs npm

# Ubuntu/Debian installs fd as fdfind.
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  ln -sf "$(command -v fdfind)" "$BIN/fd"
fi

log "PYTHON QA VENV"
python3 -m venv "$PYVENV"
"$PYVENV/bin/python" -m pip install --upgrade pip wheel setuptools >/dev/null
"$PYVENV/bin/pip" install -q \
  ruff mypy pytest pytest-asyncio bandit pip-audit pre-commit pipdeptree httpie rich

log "NODE / MINIAPP TOOLBOX"
if command -v npm >/dev/null 2>&1; then
  sudo npm install -g prettier @biomejs/biome typescript vite html-validate @playwright/test >/dev/null
  echo "node toolbox installed"
else
  echo "npm missing; node toolbox skipped"
fi

log "HELPERS"
cat > "$BIN/server-toolbox" <<'SH'
#!/usr/bin/env bash
set +e
echo "===== SERVER TOOLBOX ====="
echo "Core:"
for c in jq rg fd tree sqlite3 shellcheck yamllint htop ncdu git curl; do printf '%-14s ' "$c"; command -v "$c" || echo missing; done

echo
echo "Python QA:"
/opt/devtools/python-qa/bin/python --version 2>/dev/null || true
for c in ruff mypy pytest bandit pip-audit pre-commit pipdeptree http; do printf '%-14s ' "$c"; /opt/devtools/python-qa/bin/$c --version 2>/dev/null | head -1 || echo missing; done

echo
echo "Node/MiniApp:"
node --version 2>/dev/null || true
npm --version 2>/dev/null || true
for c in prettier biome tsc vite html-validate playwright; do printf '%-14s ' "$c"; command -v "$c" || npx -y "$c" --version 2>/dev/null | head -1 || echo missing; done

echo
echo "Main helpers:"
echo "  qa-poker            compile/test/ruff/bandit/pip-audit for poker-bot"
echo "  miniapp-check URL   curl + basic HTML response check"
echo "  telegram-bot-check  Telegram getMe/getWebhookInfo without printing token"
echo "  telegram-set-commands  set clean Telegram bot commands"
echo "SERVER_TOOLBOX_DONE"
SH

cat > "$BIN/qa-poker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
PY=.venv/bin/python
PIP=.venv/bin/pip
if [ ! -x "$PY" ]; then python3 -m venv .venv; fi
$PY -m pip install --upgrade pip >/dev/null
$PIP install -r requirements.txt >/dev/null
$PIP install ruff bandit pip-audit mypy >/dev/null

echo "===== PY COMPILE ====="
$PY -m py_compile $(find app -name '*.py')
echo "===== PYTEST ====="
$PY -m pytest -q
echo "===== RUFF ====="
.venv/bin/ruff check app tests || true
echo "===== BANDIT ====="
.venv/bin/bandit -q -r app || true
echo "===== PIP AUDIT ====="
.venv/bin/pip-audit || true
echo "QA_POKER_DONE"
SH

cat > "$BIN/miniapp-check" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url="${1:-}"
if [ -z "$url" ]; then echo "Usage: miniapp-check URL"; exit 1; fi

echo "===== CURL HEAD ====="
curl -I -L --max-time 10 "$url" | sed -n '1,40p'
echo "===== HTML SAMPLE ====="
curl -s -L --max-time 10 "$url" | head -c 1200 | sed -E 's#(TOKEN|SECRET|PASSWORD|KEY)=?[^ ]*#\1_REDACTED#g'
echo
echo "===== TOOLING ====="
command -v biome >/dev/null && biome --version || true
command -v playwright >/dev/null && playwright --version || true
echo "MINIAPP_CHECK_DONE"
SH

cat > "$BIN/telegram-bot-check" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
ENV="/opt/apps/poker-bot/.env"
TOKEN="$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV" | cut -d= -f2-)"
if [ -z "$TOKEN" ]; then echo "TELEGRAM_TOKEN_MISSING"; exit 1; fi
python3 - <<'PY'
import json, urllib.request
from pathlib import Path

env = {}
for line in Path('/opt/apps/poker-bot/.env').read_text().splitlines():
    if '=' in line and not line.strip().startswith('#'):
        k, v = line.split('=', 1)
        env[k] = v
TOKEN = env.get('TELEGRAM_BOT_TOKEN', '')
for method in ['getMe', 'getWebhookInfo']:
    with urllib.request.urlopen(f'https://api.telegram.org/bot{TOKEN}/{method}', timeout=10) as r:
        data = json.loads(r.read().decode())
    if method == 'getMe':
        result = data.get('result', {})
        print('GETME_OK:', data.get('ok'), 'username=', result.get('username'), 'id=', result.get('id'))
    else:
        result = data.get('result', {})
        safe = {k: result.get(k) for k in ['url', 'has_custom_certificate', 'pending_update_count', 'last_error_date', 'last_error_message', 'max_connections']}
        print('WEBHOOK_INFO:', json.dumps(safe, ensure_ascii=False))
PY
echo "TELEGRAM_BOT_CHECK_DONE"
SH

cat > "$BIN/telegram-set-commands" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import json, urllib.request
from pathlib import Path

env = {}
for line in Path('/opt/apps/poker-bot/.env').read_text().splitlines():
    if '=' in line and not line.strip().startswith('#'):
        k, v = line.split('=', 1)
        env[k] = v
TOKEN = env.get('TELEGRAM_BOT_TOKEN', '')
if not TOKEN:
    raise SystemExit('TELEGRAM_TOKEN_MISSING')
commands = [
    {'command': 'start', 'description': 'открыть меню'},
    {'command': 'cards', 'description': 'раздача с обменом'},
    {'command': 'topscore', 'description': 'рейтинг игры'},
    {'command': 'topduel', 'description': 'рейтинг дуэлей'},
    {'command': 'profile', 'description': 'профиль игрока'},
    {'command': 'nick', 'description': 'сменить игровой ник'},
    {'command': 'duel', 'description': 'вызвать игрока на дуэль в группе'},
    {'command': 'help', 'description': 'правила и помощь'},
]
body = json.dumps({'commands': commands}).encode()
req = urllib.request.Request(f'https://api.telegram.org/bot{TOKEN}/setMyCommands', data=body, headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(req, timeout=10) as r:
    data = json.loads(r.read().decode())
print('SET_COMMANDS_OK:', data.get('ok'))
PY
echo "TELEGRAM_SET_COMMANDS_DONE"
SH

chmod 700 "$BIN/server-toolbox" "$BIN/qa-poker" "$BIN/miniapp-check" "$BIN/telegram-bot-check" "$BIN/telegram-set-commands"

grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"

cat > /opt/data/ai-control-room/server/DEVTOOLS.md <<'MD'
# Server Devtools Stage 1

Installed safe server utilities for diagnostics and product development:

- jq, ripgrep, fd, tree, sqlite3, shellcheck, yamllint, htop, ncdu.
- Python QA venv in /opt/devtools/python-qa: ruff, mypy, pytest, bandit, pip-audit, pre-commit, pipdeptree, httpie.
- Node/MiniApp global tools: prettier, Biome, TypeScript, Vite, html-validate, Playwright test package.
- Helper commands: server-toolbox, qa-poker, miniapp-check, telegram-bot-check, telegram-set-commands.

Rules:

- Do not install heavy Playwright browsers until a Mini App visual test stage needs them.
- Do not print Telegram tokens.
- Project-local dependencies still belong in each repository, not only in global tools.
MD

server-toolbox | sed -n '1,180p'
telegram-bot-check || true

echo "SERVER_DEVTOOLS_STAGE1_DONE"
