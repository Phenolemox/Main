#!/usr/bin/env bash
set -euo pipefail

APP="/opt/apps/poker-bot"
DEPLOY="$APP/.deploy"
DATA="/opt/data/poker-redis"
CONF="$DEPLOY/poker-redis.conf"
PASS_FILE="$DEPLOY/poker-redis.pass"
PORT="6380"
BIND_IP="10.8.0.1"

log(){ printf '\n===== %s =====\n' "$1"; }

log "POKER REDIS STAGE 1"
echo "host=$(hostname) user=$(whoami) time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "PRECHECK"
if [ ! -d "$APP" ]; then
  echo "ERROR: $APP not found"
  exit 1
fi

if ! command -v redis-server >/dev/null 2>&1; then
  echo "redis-server missing, installing"
  sudo apt-get update -y
  sudo apt-get install -y redis-server redis-tools
else
  redis-server --version || true
fi

mkdir -p "$DEPLOY" "$DATA"
sudo chown -R admin:admin "$DATA" "$DEPLOY"
chmod 700 "$DEPLOY"
chmod 700 "$DATA"

log "SECRET"
if [ ! -s "$PASS_FILE" ]; then
  umask 077
  python3 - <<'PY' > "$PASS_FILE"
import secrets
print(secrets.token_urlsafe(48))
PY
fi
chmod 600 "$PASS_FILE"
REDIS_PASS="$(cat "$PASS_FILE")"
echo "redis password file exists; value is not printed"

log "CONFIG"
cat > "$CONF" <<EOF
bind 127.0.0.1 $BIND_IP
port $PORT
protected-mode yes
requirepass $REDIS_PASS
dir $DATA
dbfilename poker-redis.rdb
appendonly yes
appendfilename "poker-redis.aof"
save 900 1
save 300 10
save 60 10000
maxmemory 256mb
maxmemory-policy allkeys-lru
loglevel notice
daemonize no
supervised no
EOF
chmod 600 "$CONF"

log "SYSTEMD"
sudo tee /etc/systemd/system/poker-redis.service >/dev/null <<EOF
[Unit]
Description=Poker Bot Dedicated Redis
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=admin
Group=admin
ExecStart=/usr/bin/redis-server $CONF --daemonize no --supervised no
ExecStop=/usr/bin/redis-cli -h $BIND_IP -p $PORT -a $REDIS_PASS shutdown nosave
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=$DATA $DEPLOY
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable poker-redis.service >/dev/null
sudo systemctl restart poker-redis.service
sleep 2

log "REDIS PING"
PYBIN="$APP/.venv/bin/python"
[ -x "$PYBIN" ] || PYBIN="python3"
"$PYBIN" - <<'PY'
from pathlib import Path
import redis
p = Path('/opt/apps/poker-bot/.deploy/poker-redis.pass').read_text().strip()
r = redis.Redis(host='10.8.0.1', port=6380, password=p, db=0, decode_responses=True, socket_connect_timeout=3, socket_timeout=3)
print('POKER_REDIS_PING:', r.ping())
r.set('poker:ops:redis_stage1', 'ok', ex=3600)
print('POKER_REDIS_RW:', r.get('poker:ops:redis_stage1'))
PY

log "ENV UPDATE"
"$PYBIN" - <<'PY'
from pathlib import Path
from urllib.parse import quote

env_path = Path('/opt/apps/poker-bot/.env')
pass_path = Path('/opt/apps/poker-bot/.deploy/poker-redis.pass')
password = pass_path.read_text().strip()
url = 'redis://:' + quote(password, safe='') + '@10.8.0.1:6380/0'

lines = []
seen = False
for line in env_path.read_text(encoding='utf-8').splitlines():
    if line.startswith('REDIS_URL='):
        if not seen:
            lines.append('REDIS_URL=' + url)
            seen = True
        continue
    lines.append(line)
if not seen:
    lines.append('REDIS_URL=' + url)

env_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('ENV_REDIS_URL_UPDATED')
PY
chmod 600 "$APP/.env"

log "RESTART POKER BOT"
sudo systemctl restart poker-bot.service
sleep 3

log "CHECKS"
echo "poker-redis service:"
systemctl show poker-redis.service -p ActiveState -p SubState -p NRestarts -p MainPID -p ExecMainStatus --no-pager

echo
curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/redis && echo

echo
ss -ltnp | grep -E '(:6380|:8140|:8130|:8131)' || true

log "RECENT REDACTED LOGS"
journalctl -u poker-redis.service --since "5 minutes ago" --no-pager | tail -80 || true
journalctl -u poker-bot.service --since "5 minutes ago" --no-pager \
  | sed -E 's#bot[0-9]+:[A-Za-z0-9_-]+#bot[REDACTED]#g; s#redis://:[^@]+@#redis://:[REDACTED]@#g; s#(TOKEN|SECRET|PASSWORD|KEY)=?[^ ]*#\1_REDACTED#g' \
  | tail -120 || true

echo "POKER_REDIS_STAGE1_DONE"
