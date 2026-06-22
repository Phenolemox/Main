#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/bin:$PATH"

USER_NAME="$(whoami)"
GROUP_NAME="$(id -gn)"
MAIN_REPO="/opt/repos/Main"
SRC="$MAIN_REPO/ai_control_room_app"
APP="/opt/apps/ai-control-room"
BACKUP="/opt/backups/ai-control-room-pre-stage1-$(date -u +%Y%m%d-%H%M%S)"
LOG="/opt/logs/ai-control-room-stage1-$(date -u +%Y%m%d-%H%M%S).log"

sudo_if() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

mkdir -p /opt/logs /opt/backups
exec > >(tee "$LOG") 2>&1

echo "===== AI CONTROL ROOM STAGE1 ====="
echo "log=$LOG"

if [ ! -d "$MAIN_REPO/.git" ]; then
  mkdir -p /opt/repos
  git clone https://github.com/Phenolemox/Main.git "$MAIN_REPO"
fi

git -C "$MAIN_REPO" fetch origin main --quiet
git -C "$MAIN_REPO" checkout main >/dev/null 2>&1 || true
git -C "$MAIN_REPO" pull --ff-only origin main --quiet

test -f "$SRC/app.py" || { echo "SRC_MISSING=$SRC"; exit 1; }

if [ -d "$APP" ]; then
  mkdir -p "$BACKUP"
  cp -a "$APP/." "$BACKUP/"
  echo "PREVIOUS_APP_BACKUP=$BACKUP"
fi

mkdir -p "$APP"
rsync -a --delete \
  --exclude='.env' \
  --exclude='.venv' \
  --exclude='__pycache__' \
  "$SRC/" "$APP/"

if [ ! -f "$APP/.env" ]; then
  cp "$APP/.env.example" "$APP/.env"
  chmod 600 "$APP/.env"
fi

python3 - <<'PY'
from pathlib import Path

control_env = Path('/opt/apps/ai-control-room/.env')
poker_env = Path('/opt/apps/poker-bot/.env')

def read_env(path: Path) -> dict[str, str]:
    values = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key] = value
    return values

control = read_env(control_env)
poker = read_env(poker_env)

updates = {
    'POKER_ADMIN_BASE_URL': control.get('POKER_ADMIN_BASE_URL') or 'http://10.8.0.1:8140',
}
if not control.get('POKER_ADMIN_TOKEN') and poker.get('ADMIN_TOKEN'):
    updates['POKER_ADMIN_TOKEN'] = poker['ADMIN_TOKEN']

lines = control_env.read_text().splitlines() if control_env.exists() else []
seen = set()
new_lines = []
for line in lines:
    if '=' not in line or line.lstrip().startswith('#'):
        new_lines.append(line)
        continue
    key, _value = line.split('=', 1)
    if key in updates:
        new_lines.append(f'{key}={updates[key]}')
        seen.add(key)
    else:
        new_lines.append(line)
for key, value in updates.items():
    if key not in seen and key not in control:
        new_lines.append(f'{key}={value}')
control_env.write_text('\n'.join(new_lines) + '\n')
control_env.chmod(0o600)
PY

python3 -m venv "$APP/.venv"
"$APP/.venv/bin/python" -m pip install --upgrade pip >/dev/null
"$APP/.venv/bin/pip" install -r "$APP/requirements.txt" >/dev/null

sudo_if chown -R "$USER_NAME:$GROUP_NAME" "$APP"

sudo_if tee /etc/systemd/system/ai-control-room.service >/dev/null <<'UNIT'
[Unit]
Description=AI Control Room Web UI
After=network-online.target ai-agent-api.service poker-bot.service
Wants=network-online.target

[Service]
Type=simple
User=admin
Group=admin
WorkingDirectory=/opt/apps/ai-control-room
EnvironmentFile=-/opt/apps/ai-control-room/.env
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/apps/ai-control-room/.venv/bin/uvicorn app:app --host ${CONTROL_ROOM_HOST} --port ${CONTROL_ROOM_PORT}
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

sudo_if systemctl daemon-reload
sudo_if systemctl enable ai-control-room.service >/dev/null
sudo_if systemctl restart ai-control-room.service
sleep 2

systemctl --no-pager --full status ai-control-room.service | sed -n '1,40p'
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8150/health)"
curl -fsS --max-time 5 http://10.8.0.1:8150/api/summary >/tmp/ai-control-room-summary.json
python3 -m json.tool /tmp/ai-control-room-summary.json | sed -n '1,80p'

echo "AI_CONTROL_ROOM_STAGE1_DONE"
