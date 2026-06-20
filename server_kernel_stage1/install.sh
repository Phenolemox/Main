#!/usr/bin/env bash
set -euo pipefail

log(){ printf '\n===== %s =====\n' "$1"; }

log "SERVER KERNEL STAGE 1"
echo "host=$(hostname) user=$(whoami) time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "SYSCTL CONFIG"
sudo tee /etc/sysctl.d/99-ai-control-room.conf >/dev/null <<'EOF'
# AI Control Room / poker-bot runtime baseline
# Redis needs overcommit to avoid background save / AOF rewrite failures under memory pressure.
vm.overcommit_memory = 1

# Bigger listen backlog for async APIs / reverse proxies / Redis.
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096

# Keep swapping low on small VPS nodes.
vm.swappiness = 10

# Larger global file handle ceiling for many bot/network connections.
fs.file-max = 1048576
EOF

sudo sysctl --system >/tmp/ai-sysctl-stage1.log
cat /tmp/ai-sysctl-stage1.log | tail -80

log "SYSTEMD LIMITS"
sudo mkdir -p /etc/systemd/system/poker-bot.service.d /etc/systemd/system/poker-redis.service.d
sudo tee /etc/systemd/system/poker-bot.service.d/override.conf >/dev/null <<'EOF'
[Service]
LimitNOFILE=65535
Restart=always
RestartSec=3
EOF
sudo tee /etc/systemd/system/poker-redis.service.d/override.conf >/dev/null <<'EOF'
[Service]
LimitNOFILE=65535
Restart=always
RestartSec=3
EOF

sudo systemctl daemon-reload
sudo systemctl restart poker-redis.service
sleep 2
sudo systemctl restart poker-bot.service
sleep 3

log "CHECK SYSCTL"
sysctl vm.overcommit_memory net.core.somaxconn net.ipv4.tcp_max_syn_backlog vm.swappiness fs.file-max

log "CHECK SERVICES"
systemctl show poker-redis.service -p ActiveState -p SubState -p NRestarts -p MainPID -p ExecMainStatus -p LimitNOFILE --no-pager
systemctl show poker-bot.service -p ActiveState -p SubState -p NRestarts -p MainPID -p ExecMainStatus -p LimitNOFILE --no-pager

log "CHECK ENDPOINTS"
curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/redis && echo

log "RECENT WARNINGS"
journalctl -u poker-redis.service --since "3 minutes ago" --no-pager | tail -80 || true
journalctl -u poker-bot.service --since "3 minutes ago" --no-pager \
  | sed -E 's#bot[0-9]+:[A-Za-z0-9_-]+#bot[REDACTED]#g; s#redis://:[^@]+@#redis://:[REDACTED]@#g; s#(TOKEN|SECRET|PASSWORD|KEY)=?[^ ]*#\1_REDACTED#g' \
  | tail -120 || true

echo "SERVER_KERNEL_STAGE1_DONE"
