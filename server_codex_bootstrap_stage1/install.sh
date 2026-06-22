#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/bin:$PATH"

USER_NAME="$(whoami)"
GROUP_NAME="$(id -gn)"
BIN="$HOME/bin"
LOG_DIR="/opt/logs"
CTX="/opt/data/ai-control-room/server"
REPOS="/opt/repos"
APPS="/opt/apps"
REPORTS="/opt/data/ai-control-room/reports"
LOG="$LOG_DIR/server_codex_bootstrap_stage1_$(date -u +%Y%m%d-%H%M%S).log"
CODEX_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKUl+GchAk/BBDCsV+d4QWlwjPNtVudq+de+JG1YtUeq codex-ai-server-20260622"

sudo_if() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

mkdir -p "$BIN"
sudo_if install -d -m 755 -o "$USER_NAME" -g "$GROUP_NAME" "$LOG_DIR" "$CTX" "$REPOS" "$APPS" "$REPORTS"
exec > >(tee "$LOG") 2>&1

section() { printf '\n===== %s =====\n' "$1"; }

section "SERVER CODEX BOOTSTRAP STAGE 1"
echo "host=$(hostname)"
echo "user=$USER_NAME"
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "log=$LOG"

section "SSH ACCESS KEY"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
if grep -qxF "$CODEX_PUBKEY" "$HOME/.ssh/authorized_keys"; then
  echo "CODEX_SSH_KEY_ALREADY_PRESENT"
else
  printf '%s\n' "$CODEX_PUBKEY" >> "$HOME/.ssh/authorized_keys"
  echo "CODEX_SSH_KEY_ADDED"
fi

section "APT TOOLBOX"
if command -v apt-get >/dev/null 2>&1; then
  sudo_if apt-get update -y
  sudo_if apt-get -f install -y || true
  sudo_if apt-get install -y --no-install-recommends \
    ca-certificates curl git jq rsync tar unzip zip \
    ripgrep fd-find tree sqlite3 htop ncdu make build-essential \
    python3 python3-venv python3-pip
else
  echo "APT_GET_MISSING"
fi
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  ln -sf "$(command -v fdfind)" "$BIN/fd"
fi

section "GLOBAL GIT SETTINGS"
git config --global user.name "AI Server"
git config --global user.email "ai-server@localhost"
git config --global pull.ff only
git config --global init.defaultBranch main
git config --global --add safe.directory "$REPOS/poker-bot" || true
git config --global --add safe.directory "$APPS/poker-bot" || true
git config --global --add safe.directory "$REPOS/Main" || true
git --version

section "HELPERS"
cat > "$BIN/ai-stage" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/bin:$PATH"

url="${1:-}"
if [ -z "$url" ]; then
  echo "Usage: ai-stage URL [args...]"
  exit 2
fi
shift || true

mkdir -p /opt/logs
log="/opt/logs/ai-stage-$(date -u +%Y%m%d-%H%M%S).log"
tmp="/tmp/ai-stage-$$.sh"
export AI_STAGE_URL="$url"
export AI_STAGE_LOG="$log"

exec > >(tee "$log") 2>&1
echo "AI_STAGE_URL=$AI_STAGE_URL"
echo "AI_STAGE_LOG=$AI_STAGE_LOG"

if printf '%s' "$url" | grep -Eq '^https?://'; then
  if ! curl -fsSL "$url" -o "$tmp"; then
    status=$?
    echo "AI_STAGE_DOWNLOAD_FAIL=$status"
    echo "AI_STAGE_EXIT=$status"
    echo "AI_STAGE_LOG=$log"
    exit "$status"
  fi
else
  if ! cp "$url" "$tmp"; then
    status=$?
    echo "AI_STAGE_COPY_FAIL=$status"
    echo "AI_STAGE_EXIT=$status"
    echo "AI_STAGE_LOG=$log"
    exit "$status"
  fi
fi
sed -i 's/\r$//' "$tmp"
chmod 700 "$tmp"

set +e
bash "$tmp" "$@"
status=$?
echo "AI_STAGE_EXIT=$status"
echo "AI_STAGE_LOG=$log"
exit "$status"
SH

cat > "$BIN/ai-tail" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
latest="$(ls -1t /opt/logs/ai-stage-*.log /opt/logs/*stage*.log 2>/dev/null | head -1 || true)"
if [ -z "$latest" ]; then
  echo "NO_STAGE_LOGS"
  exit 1
fi
echo "log=$latest"
tail -n "${1:-80}" "$latest"
SH

cat > "$BIN/server-quick" <<'SH'
#!/usr/bin/env bash
set +e
echo "===== SERVER QUICK ====="
echo "host=$(hostname)"
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "user=$(whoami)"
echo
echo "----- OS -----"
lsb_release -a 2>/dev/null || cat /etc/os-release
echo
echo "----- DISK -----"
df -h /
echo
echo "----- MEMORY -----"
free -h
echo
echo "----- LOAD -----"
uptime
echo
echo "----- TOOLS -----"
for c in git curl jq rg fd tree sqlite3 python3 systemctl; do
  printf '%-12s ' "$c"; command -v "$c" || echo missing
done
echo
echo "----- POKER SERVICE -----"
systemctl is-active poker-bot.service 2>/dev/null || true
systemctl --no-pager --full status poker-bot.service 2>/dev/null | sed -n '1,25p'
echo
echo "----- HEALTH -----"
curl -s --max-time 5 http://10.8.0.1:8140/health; echo
curl -s --max-time 5 http://10.8.0.1:8140/ready; echo
echo "SERVER_QUICK_DONE"
SH

cat > "$BIN/ai-repo-check" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
echo "===== AI REPO CHECK ====="
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "----- GITHUB CLI -----"
if command -v gh >/dev/null 2>&1; then
  gh --version | head -1
  gh auth status 2>&1 | sed -E 's/(token: )[A-Za-z0-9_:-]+/\1REDACTED/g'
else
  echo "GH_MISSING"
fi
echo
for repo in /opt/repos/Main /opt/repos/poker-bot /opt/apps/poker-bot; do
  echo "----- $repo -----"
  if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$repo" remote -v | sed -n '1,4p'
    git -C "$repo" fetch origin main --quiet || true
    echo "head=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo none)"
    echo "origin_main=$(git -C "$repo" rev-parse --short origin/main 2>/dev/null || echo none)"
    git -C "$repo" status --short | sed -n '1,30p'
    git -C "$repo" log --oneline -3 2>/dev/null || true
  else
    echo "NOT_GIT"
  fi
  echo
done
echo "AI_REPO_CHECK_DONE"
SH

cat > "$BIN/ai-ensure-repos" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
mkdir -p /opt/repos

ensure_repo() {
  repo="$1"
  path="$2"
  if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "REPO_EXISTS=$path"
    git -C "$path" fetch origin main --quiet || true
    git -C "$path" checkout main >/dev/null 2>&1 || true
    git -C "$path" config pull.ff only || true
    return 0
  fi
  if [ -e "$path" ]; then
    backup="${path}.bak.$(date -u +%Y%m%d-%H%M%S)"
    mv "$path" "$backup"
    echo "MOVED_NON_GIT_PATH_TO=$backup"
  fi
  if command -v gh >/dev/null 2>&1; then
    gh repo clone "$repo" "$path" && return 0
  fi
  git clone "https://github.com/$repo.git" "$path"
}

ensure_repo Phenolemox/Main /opt/repos/Main
ensure_repo Phenolemox/poker-bot /opt/repos/poker-bot
git config --global --add safe.directory /opt/repos/Main || true
git config --global --add safe.directory /opt/repos/poker-bot || true
ai-repo-check
echo "AI_ENSURE_REPOS_DONE"
SH

cat > "$BIN/ai-sync-check" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
REPO="/opt/repos/poker-bot"
APP="/opt/apps/poker-bot"

redact() {
  sed -E 's/(TOKEN|SECRET|PASSWORD|KEY|DATABASE_URL|REDIS_URL)=([^ ]+)/\1=REDACTED/g'
}

echo "===== AI SYNC CHECK ====="
echo "host=$(hostname)"
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo
echo "----- REPO -----"
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" fetch origin main --quiet || true
  repo_full="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo NO_REPO_HEAD)"
  origin_full="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || echo NO_ORIGIN_MAIN)"
  echo "repo_head=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo none)"
  echo "origin_main=$(git -C "$REPO" rev-parse --short origin/main 2>/dev/null || echo none)"
  git -C "$REPO" status --short | sed -n '1,40p'
else
  repo_full="NO_REPO"
  origin_full="NO_ORIGIN"
  echo "REPO_MISSING=$REPO"
fi

echo
echo "----- APP -----"
if git -C "$APP" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  app_full="$(git -C "$APP" rev-parse HEAD 2>/dev/null || echo NO_APP_HEAD)"
  echo "app_head=$(git -C "$APP" rev-parse --short HEAD 2>/dev/null || echo none)"
  git -C "$APP" status --short | sed -n '1,40p'
else
  app_full="APP_NOT_GIT"
  echo "APP_NOT_GIT=$APP"
  if [ -d "$REPO" ] && [ -d "$APP" ]; then
    rsync -ani --delete \
      --exclude='.git/' --exclude='.venv/' --exclude='__pycache__/' \
      --exclude='.pytest_cache/' --exclude='.env' --exclude='*.db' \
      --exclude='*.sqlite' --exclude='*.sqlite.gz' \
      "$REPO/" "$APP/" | sed -n '1,60p'
  fi
fi

echo
echo "----- SERVICE -----"
exec_start="$(systemctl show poker-bot.service -p ExecStart --value 2>/dev/null | redact)"
main_pid="$(systemctl show poker-bot.service -p MainPID --value 2>/dev/null)"
echo "MainPID=${main_pid:-unknown}"
echo "ExecStart=${exec_start:-unknown}"

echo
echo "----- HEALTH -----"
health="$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
ready="$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "health=$health"
echo "ready=$ready"

echo
echo "----- RESULT -----"
[ "$repo_full" = "$origin_full" ] && echo "REPO_ORIGIN_SYNC_OK" || echo "REPO_ORIGIN_SYNC_CHECK"
if [ "$app_full" = "APP_NOT_GIT" ]; then
  echo "APP_REPO_SYNC_CHECK_NEEDED"
else
  [ "$app_full" = "$repo_full" ] && echo "APP_REPO_SYNC_OK" || echo "APP_REPO_SYNC_CHECK"
fi
printf '%s' "$health" | grep -q '"healthy"\|"status":"healthy"' && echo "HEALTH_OK" || echo "HEALTH_CHECK_NEEDED"
echo "AI_SYNC_CHECK_DONE"
SH

cat > "$BIN/poker-qa" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/bin:$PATH"
cd /opt/repos/poker-bot
PY="./.venv/bin/python"
PIP="./.venv/bin/pip"
if [ ! -x "$PY" ]; then
  python3 -m venv .venv
fi
"$PY" -m pip install --upgrade pip >/dev/null
"$PIP" install -r requirements.txt >/dev/null
echo "===== PY COMPILE ====="
"$PY" -m py_compile $(find app -name '*.py')
echo "PY_COMPILE_OK"
echo "===== PYTEST ====="
"$PY" -m pytest -q
echo "PYTEST_OK"
echo "POKER_QA_DONE"
SH

cat > "$BIN/poker-deploy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/bin:$PATH"
ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health
echo "POKER_DEPLOY_DONE"
SH

cat > "$BIN/poker-stage26" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/bin:$PATH"
ai-stage https://raw.githubusercontent.com/Phenolemox/Main/main/pokerbot_v3_clean_stage26_linux/install.sh
SH

cat > "$BIN/poker-reset-sessions" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
PY="./.venv/bin/python"
[ -x "$PY" ] || PY=python3
"$PY" - <<'PY'
from app.bot.session_state import sessions
client = sessions._client()
keys = list(client.scan_iter(match="poker:session:*", count=500)) if client else []
if client and keys:
    client.delete(*keys)
print("SESSION_RESET=" + str(len(keys)))
PY
SH

cat > "$BIN/bots-list" <<'SH'
#!/usr/bin/env bash
set +e
echo "===== BOTS AND APPS ====="
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "----- systemd candidates -----"
systemctl list-units --type=service --all --no-pager |
  awk '/bot|api|site|mcp|control-room|redis/ {print $1, $3, $4, substr($0, index($0,$5))}' |
  sed -n '1,160p'
echo
echo "----- /opt/apps -----"
find /opt/apps -maxdepth 2 -type d -name .git -prune -o -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort
echo
echo "----- listening app ports -----"
ss -ltnp 2>/dev/null | awk '/10\.8\.0\.1/ {print}' | sed -n '1,120p'
echo
echo "----- known health endpoints -----"
for url in \
  http://10.8.0.1:8130/health \
  http://10.8.0.1:8140/health \
  http://10.8.0.1:19999/api/v1/info
do
  printf '%s ' "$url"
  curl -s --max-time 5 "$url" | head -c 180
  echo
done
echo "BOTS_LIST_DONE"
SH

cat > "$BIN/ai-mcp-check" <<'SH'
#!/usr/bin/env bash
set +e
echo "===== AI MCP CHECK ====="
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
systemctl is-active ai-mcp-bridge.service 2>/dev/null
systemctl --no-pager --full status ai-mcp-bridge.service 2>/dev/null | sed -n '1,30p'
echo
echo "----- bridge files -----"
find /opt/apps/ai-mcp-bridge -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
echo
echo "----- port -----"
ss -ltnp 2>/dev/null | grep ':8131' || true
echo
echo "----- agent api health through direct API -----"
curl -s --max-time 5 http://10.8.0.1:8130/health
echo
echo "AI_MCP_CHECK_DONE"
SH

cat > "$BIN/ai-backup-now" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "===== AI BACKUP NOW ====="
echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -x /opt/scripts/backup-ai-server.sh ]; then
  sudo /opt/scripts/backup-ai-server.sh
else
  echo "BACKUP_SCRIPT_MISSING=/opt/scripts/backup-ai-server.sh"
  exit 1
fi
echo
echo "----- newest backup files -----"
find /opt/backups -maxdepth 4 -type f -ls 2>/dev/null | sort -k11 | tail -40
echo "AI_BACKUP_NOW_DONE"
SH

cat > "$BIN/telegram-bot-check" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import json
import urllib.request
from pathlib import Path

paths = [Path('/opt/apps/poker-bot/.env'), Path('/opt/repos/poker-bot/.env')]
env = {}
for path in paths:
    if path.exists():
        for line in path.read_text().splitlines():
            if '=' in line and not line.strip().startswith('#'):
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
        break

token = env.get('TELEGRAM_BOT_TOKEN') or env.get('BOT_TOKEN') or ''
if not token:
    raise SystemExit('TELEGRAM_TOKEN_MISSING')

for method in ('getMe', 'getWebhookInfo'):
    with urllib.request.urlopen(f'https://api.telegram.org/bot{token}/{method}', timeout=10) as r:
        data = json.loads(r.read().decode())
    if method == 'getMe':
        result = data.get('result', {})
        print('GETME_OK:', data.get('ok'), 'username=', result.get('username'), 'id=', result.get('id'))
    else:
        result = data.get('result', {})
        safe = {k: result.get(k) for k in ('url', 'pending_update_count', 'last_error_date', 'last_error_message', 'max_connections')}
        print('WEBHOOK_INFO:', json.dumps(safe, ensure_ascii=False))
PY
echo "TELEGRAM_BOT_CHECK_DONE"
SH

cat > "$BIN/telegram-set-commands" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import json
import urllib.request
from pathlib import Path

paths = [Path('/opt/apps/poker-bot/.env'), Path('/opt/repos/poker-bot/.env')]
env = {}
for path in paths:
    if path.exists():
        for line in path.read_text().splitlines():
            if '=' in line and not line.strip().startswith('#'):
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
        break

token = env.get('TELEGRAM_BOT_TOKEN') or env.get('BOT_TOKEN') or ''
if not token:
    raise SystemExit('TELEGRAM_TOKEN_MISSING')

commands = [
    {'command': 'start', 'description': '\u043c\u0435\u043d\u044e'},
    {'command': 'cards', 'description': '\u0440\u0430\u0437\u0434\u0430\u0447\u0430 \u0441 \u043e\u0431\u043c\u0435\u043d\u043e\u043c'},
    {'command': 'tops', 'description': '\u0440\u0435\u0439\u0442\u0438\u043d\u0433\u0438'},
    {'command': 'topscore', 'description': '\u0440\u0435\u0439\u0442\u0438\u043d\u0433 \u0438\u0433\u0440\u044b'},
    {'command': 'topduel', 'description': '\u0440\u0435\u0439\u0442\u0438\u043d\u0433 \u0434\u0443\u044d\u043b\u0435\u0439'},
    {'command': 'profile', 'description': '\u043f\u0440\u043e\u0444\u0438\u043b\u044c'},
    {'command': 'nick', 'description': '\u0438\u0433\u0440\u043e\u0432\u043e\u0439 \u043d\u0438\u043a'},
    {'command': 'duel', 'description': '\u0434\u0443\u044d\u043b\u044c \u0432 \u0433\u0440\u0443\u043f\u043f\u0435'},
    {'command': 'admin', 'description': '\u0430\u0434\u043c\u0438\u043d-\u043f\u0430\u043d\u0435\u043b\u044c'},
]
body = json.dumps({'commands': commands}, ensure_ascii=False).encode()
req = urllib.request.Request(
    f'https://api.telegram.org/bot{token}/setMyCommands',
    data=body,
    headers={'Content-Type': 'application/json'},
)
with urllib.request.urlopen(req, timeout=10) as r:
    data = json.loads(r.read().decode())
print('SET_COMMANDS_OK:', data.get('ok'))
PY
echo "TELEGRAM_SET_COMMANDS_DONE"
SH

chmod 700 \
  "$BIN/ai-stage" "$BIN/ai-tail" "$BIN/server-quick" "$BIN/ai-repo-check" \
  "$BIN/ai-ensure-repos" "$BIN/ai-sync-check" "$BIN/poker-qa" \
  "$BIN/poker-deploy" "$BIN/poker-stage26" "$BIN/poker-reset-sessions" \
  "$BIN/bots-list" "$BIN/ai-mcp-check" "$BIN/ai-backup-now" \
  "$BIN/telegram-bot-check" "$BIN/telegram-set-commands"

grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"

cat > "$CTX/README.md" <<'MD'
# AI Server Control Room

Installed commands:
- `server-quick` - OS, service and API health.
- `ai-stage URL` - run a raw GitHub stage with a log in `/opt/logs`.
- `ai-tail [N]` - print the newest stage log tail.
- `ai-ensure-repos` - clone/fetch `Phenolemox/Main` and `Phenolemox/poker-bot`.
- `ai-repo-check` - inspect GitHub/repo state without printing secrets.
- `ai-sync-check` - compare `/opt/repos/poker-bot`, `/opt/apps/poker-bot`, service and health.
- `poker-qa` - py_compile and pytest for `/opt/repos/poker-bot`.
- `poker-deploy` - deploy `Phenolemox/poker-bot`.
- `poker-stage26` - install the current v3 poker bot stage.
- `poker-reset-sessions` - clear live Redis poker sessions.
- `bots-list` - list managed bot/app/service candidates.
- `ai-mcp-check` - check the MCP bridge service and port.
- `ai-backup-now` - run the server backup script and list newest backup files.
- `telegram-bot-check` and `telegram-set-commands`.
MD

section "SERVER QUICK"
server-quick || true

section "ENSURE REPOS"
ai-ensure-repos || true

section "SYNC CHECK"
ai-sync-check || true

section "TELEGRAM CHECK"
telegram-bot-check || true

echo "SERVER_CODEX_BOOTSTRAP_STAGE1_DONE"
