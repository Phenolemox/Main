#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/bin:$PATH"

USER_NAME="$(whoami)"
MAIN_REPO="/opt/repos/Main"
LOG="/opt/logs/bots-platform-stage1-$(date -u +%Y%m%d-%H%M%S).log"
SECRETS="/opt/secrets/bots-platform.env"

sudo_if() {
  if [ "$(id -u)" = "0" ]; then "$@"; else sudo "$@"; fi
}

mkdir -p /opt/logs /opt/data/cb-balloons /opt/data/autobot /opt/secrets
exec > >(tee "$LOG") 2>&1

echo "===== BOTS PLATFORM STAGE1 ====="
echo "log=$LOG"

if [ ! -d "$MAIN_REPO/.git" ]; then
  mkdir -p /opt/repos
  git clone https://github.com/Phenolemox/Main.git "$MAIN_REPO"
fi

git -C "$MAIN_REPO" fetch origin main --quiet
git -C "$MAIN_REPO" checkout main >/dev/null 2>&1 || true
git -C "$MAIN_REPO" pull --ff-only origin main --quiet || true

deploy_service() {
  local name="$1"
  local src="$MAIN_REPO/$2"
  local app="/opt/apps/$name"
  local port="$3"
  local module="$4"
  test -d "$src" || { echo "SRC_MISSING=$src"; exit 1; }
  mkdir -p "$app"
  rsync -a --delete \
    --exclude='.env' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='*.db' \
    "$src/" "$app/"
  if [ ! -f "$app/.env" ] && [ -f "$app/.env.example" ]; then
    cp "$app/.env.example" "$app/.env"
    chmod 600 "$app/.env"
  fi
  python3 -m venv "$app/.venv"
  "$app/.venv/bin/pip" install --upgrade pip >/dev/null
  "$app/.venv/bin/pip" install -r "$app/requirements.txt" >/dev/null
  sudo_if chown -R "$USER_NAME:$USER_NAME" "$app"
  sudo_if tee "/etc/systemd/system/${name}.service" >/dev/null <<UNIT
[Unit]
Description=${name} service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
WorkingDirectory=${app}
EnvironmentFile=-${app}/.env
EnvironmentFile=-${SECRETS}
Environment=PYTHONUNBUFFERED=1
ExecStart=${app}/.venv/bin/uvicorn ${module} --host 10.8.0.1 --port ${port} --loop asyncio
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
  echo "DEPLOYED=${name} port=${port}"
}

deploy_service "cb-balloons-bot" "cb_balloons_bot" "8160" "app.main:app"
deploy_service "autobot-bot" "autobot_bot" "8161" "app.main:app"
deploy_service "bots-hub" "bots_hub" "8170" "app:app"

# Control room refresh
bash "$MAIN_REPO/ai_control_room_stage1/install.sh"

python3 - <<'PY'
from pathlib import Path

secrets = Path('/opt/secrets/bots-platform.env')
cb_env = Path('/opt/apps/cb-balloons-bot/.env')
auto_env = Path('/opt/apps/autobot-bot/.env')
control_env = Path('/opt/apps/ai-control-room/.env')

def read_env(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out

sec = read_env(secrets)
cb = read_env(cb_env)
auto = read_env(auto_env)
ctrl = read_env(control_env)

cb_updates = {
    'TELEGRAM_MINI_APP_URL': cb.get('TELEGRAM_MINI_APP_URL') or 'http://10.8.0.1:8160/miniapp',
    'MAX_APP_URL': cb.get('MAX_APP_URL') or 'http://10.8.0.1:8160/miniapp',
    'DB_FILE': cb.get('DB_FILE') or '/opt/data/cb-balloons/balloon_game.db',
}
auto_updates = {
    'TELEGRAM_MINI_APP_URL': auto.get('TELEGRAM_MINI_APP_URL') or 'http://10.8.0.1:8161/miniapp',
    'MAX_APP_URL': auto.get('MAX_APP_URL') or 'http://10.8.0.1:8161/miniapp',
    'DB_FILE': auto.get('DB_FILE') or '/opt/data/autobot/autobot.db',
}
if sec.get('CB_BALLOONS_TELEGRAM_TOKEN'):
    cb_updates['TELEGRAM_BOT_TOKEN'] = sec['CB_BALLOONS_TELEGRAM_TOKEN']
if sec.get('AUTOBOT_TELEGRAM_TOKEN'):
    auto_updates['TELEGRAM_BOT_TOKEN'] = sec['AUTOBOT_TELEGRAM_TOKEN']
if sec.get('CB_BALLOONS_ADMIN_TOKEN'):
    cb_updates['ADMIN_TOKEN'] = sec['CB_BALLOONS_ADMIN_TOKEN']
    ctrl.setdefault('CB_BALLOONS_ADMIN_TOKEN', sec['CB_BALLOONS_ADMIN_TOKEN'])
if sec.get('AUTOBOT_ADMIN_TOKEN'):
    auto_updates['ADMIN_TOKEN'] = sec['AUTOBOT_ADMIN_TOKEN']
    ctrl.setdefault('AUTOBOT_ADMIN_TOKEN', sec['AUTOBOT_ADMIN_TOKEN'])

def merge(path: Path, updates: dict[str, str]) -> None:
    lines = path.read_text().splitlines() if path.exists() else []
    seen = set()
    new_lines = []
    for line in lines:
        if '=' in line and not line.lstrip().startswith('#'):
            key = line.split('=', 1)[0].strip()
            if key in updates:
                new_lines.append(f'{key}={updates[key]}')
                seen.add(key)
                continue
        new_lines.append(line)
    for key, value in updates.items():
        if key not in seen:
            new_lines.append(f'{key}={value}')
    path.write_text('\n'.join(new_lines) + '\n')
    path.chmod(0o600)

merge(cb_env, cb_updates)
merge(auto_env, auto_updates)
if control_env.exists():
    merge(control_env, {k: v for k, v in ctrl.items() if k.startswith(('CB_BALLOONS_', 'AUTOBOT_'))})
PY

sudo_if systemctl daemon-reload
for svc in cb-balloons-bot autobot-bot bots-hub; do
  sudo_if systemctl enable "${svc}.service" >/dev/null
  sudo_if systemctl restart "${svc}.service"
done

sleep 3
for url in \
  http://10.8.0.1:8160/health \
  http://10.8.0.1:8161/health \
  http://10.8.0.1:8170/health \
  http://10.8.0.1:8150/health; do
  echo "health ${url}=$(curl -s --max-time 5 "${url}")"
done

poker-qa || true
echo "BOTS_PLATFORM_STAGE1_DONE"
