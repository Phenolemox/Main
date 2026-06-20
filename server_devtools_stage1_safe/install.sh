#!/usr/bin/env bash
set -euo pipefail

log(){ printf '\n===== %s =====\n' "$1"; }

DEVROOT="/opt/devtools"
PYVENV="$DEVROOT/python-qa"
BIN="$HOME/bin"
USER_NAME="$(whoami)"
GROUP_NAME="$(id -gn)"

log "SERVER DEVTOOLS STAGE 1 SAFE"
echo "host=$(hostname) user=$USER_NAME time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "ROOT PATHS"
mkdir -p "$BIN"
sudo install -d -m 755 -o "$USER_NAME" -g "$GROUP_NAME" "$DEVROOT"
sudo install -d -m 755 -o "$USER_NAME" -g "$GROUP_NAME" /opt/data/ai-control-room/server

test -w "$DEVROOT" || { echo "DEVROOT_NOT_WRITABLE: $DEVROOT"; exit 1; }

log "APT REPAIR + CORE TOOLBOX"
sudo apt-get update -y
sudo apt-get -f install -y || true
# Do NOT apt-install npm here: this server already has NodeSource nodejs 22.x, and Ubuntu npm conflicts with it.
sudo apt-get install -y --no-install-recommends \
  jq ripgrep fd-find tree sqlite3 shellcheck yamllint htop ncdu unzip zip make curl git \
  python3-venv python3-pip ca-certificates

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  ln -sf "$(command -v fdfind)" "$BIN/fd"
fi

log "PYTHON QA VENV"
python3 -m venv "$PYVENV"
"$PYVENV/bin/python" -m pip install --upgrade pip wheel setuptools >/dev/null
"$PYVENV/bin/pip" install -q \
  ruff mypy pytest pytest-asyncio bandit pip-audit pre-commit pipdeptree httpie rich

log "NODE / MINIAPP TOOLBOX"
if command -v node >/dev/null 2>&1; then
  node --version || true
else
  echo "NODE_MISSING: skipped node miniapp tools"
fi

if command -v npm >/dev/null 2>&1; then
  npm --version || true
  sudo npm install -g prettier @biomejs/biome typescript vite html-validate @playwright/test >/dev/null
  echo "NODE_TOOLBOX_INSTALLED"
else
  echo "NPM_MISSING: skipped global JS/MiniApp tools; will install later only if needed"
fi

log "HELPERS"
cat > "$BIN/server-toolbox" <<'SH'
#!/usr/bin/env bash
set +e
echo "===== SERVER TOOLBOX ====="
echo "Core:"
for c in jq rg fd tree sqlite3 shellcheck yamllint htop ncdu git curl; do printf '%-16s ' "$c"; command -v "$c" || echo missing; done

echo
echo "Python QA:"
/opt/devtools/python-qa/bin/python --version 2>/dev/null || true
for c in ruff mypy pytest bandit pip-audit pre-commit pipdeptree http; do printf '%-16s ' "$c"; /opt/devtools/python-qa/bin/$c --version 2>/dev/null | head -1 || echo missing; done

echo
echo "Node/MiniApp:"
node --version 2>/dev/null || echo node_missing
npm --version 2>/dev/null || echo npm_missing
for c in prettier biome tsc vite html-validate playwright; do printf '%-16s ' "$c"; command -v "$c" || echo missing; done

echo
echo "Helpers:"
echo "  server-ops"
echo "  server-logs SERVICE [SINCE]"
echo "  qa-poker"
echo "  miniapp-check URL"
echo "  telegram-bot-check"
echo "  telegram-set-commands"
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
curl -I -L --max-time 10 "$url" | sed -n '1,40p'
echo
curl -s -L --max-time 10 "$url" | head -c 1200 | sed -E 's#(TOKEN|SECRET|PASSWORD|KEY)=?[^ ]*#\1_REDACTED#g'
echo
echo "MINIAPP_CHECK_DONE"
SH

cat > "$BIN/telegram-bot-check" <<'SH'
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
for method in ['getMe', 'getWebhookInfo']:
    with urllib.request.urlopen(f'https://api.telegram.org/bot{TOKEN}/{method}', timeout=10) as r:
        data = json.loads(r.read().decode())
    if method == 'getMe':
        result = data.get('result', {})
        print('GETME_OK:', data.get('ok'), 'username=', result.get('username'), 'id=', result.get('id'))
    else:
        result = data.get('result', {})
        safe = {k: result.get(k) for k in ['url', 'pending_update_count', 'last_error_date', 'last_error_message', 'max_connections']}
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
# Server Devtools Stage 1 Safe

Installed safe utilities:
- jq, ripgrep, fd, tree, sqlite3, shellcheck, yamllint, htop, ncdu.
- Python QA venv: /opt/devtools/python-qa with ruff, mypy, pytest, bandit, pip-audit, pre-commit, pipdeptree, httpie, rich.
- Node/MiniApp globals are installed only if npm already exists. This avoids the NodeSource nodejs vs Ubuntu npm apt conflict.
- Helpers: server-toolbox, qa-poker, miniapp-check, telegram-bot-check, telegram-set-commands.
MD

server-toolbox | sed -n '1,200p'
telegram-bot-check || true

echo "SERVER_DEVTOOLS_STAGE1_SAFE_DONE"
