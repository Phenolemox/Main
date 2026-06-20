#!/usr/bin/env bash
set -euo pipefail

BIN="$HOME/bin"
CTX="/opt/data/ai-control-room/server"
mkdir -p "$BIN" "$CTX" /opt/logs /opt/data/ai-control-room/reports

echo "===== AI SERVER WORKBENCH STAGE 3 ====="
echo "host=$(hostname) user=$(whoami) time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$BIN/ai-stage" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url="${1:-}"
if [ -z "$url" ]; then
  echo "Usage: ai-stage https://raw.githubusercontent.com/.../install.sh"
  exit 1
fi
mkdir -p /opt/logs /tmp/ai-stages
id="ai-stage-$(date -u +%Y%m%d-%H%M%S)"
script="/tmp/ai-stages/$id.sh"
log="/opt/logs/$id.log"
echo "AI_STAGE_URL=$url"
echo "AI_STAGE_LOG=$log"
curl -fsSL "$url" -o "$script"
chmod 700 "$script"
set +e
bash "$script" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e
echo "AI_STAGE_EXIT=$code"
echo "AI_STAGE_LOG=$log"
exit "$code"
SH

cat > "$BIN/ai-stage-tail" <<'SH'
#!/usr/bin/env bash
set +e
log="${1:-$(ls -t /opt/logs/ai-stage-*.log 2>/dev/null | head -1)}"
[ -n "$log" ] || { echo "NO_AI_STAGE_LOG"; exit 1; }
echo "AI_STAGE_LOG=$log"
tail -n "${2:-160}" "$log" | nl -ba | redact
SH

cat > "$BIN/server-screen" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
line(){ printf '\n===== %s =====\n' "$1"; }

line "CORE"
printf 'host: '; hostname
printf 'time: '; date -u +%Y-%m-%dT%H:%M:%SZ
uptime | sed 's/^/uptime: /'
free -h | awk 'NR==2{print "mem: used=" $3 " free=" $4 " available=" $7}'
df -h / | awk 'NR==2{print "disk: used=" $3 " free=" $4 " use=" $5}'

line "SERVICES"
for svc in poker-bot.service poker-redis.service ai-agent-api.service ai-mcp-bridge.service docker.service; do
  systemctl is-active --quiet "$svc" && state="active" || state="DOWN"
  restarts=$(systemctl show "$svc" -p NRestarts --value 2>/dev/null)
  mainpid=$(systemctl show "$svc" -p MainPID --value 2>/dev/null)
  printf '%-24s %-8s restarts=%s pid=%s\n' "$svc" "$state" "${restarts:-?}" "${mainpid:-?}"
done

line "ENDPOINTS"
for u in \
  http://10.8.0.1:8140/health \
  http://10.8.0.1:8140/ready \
  http://10.8.0.1:8140/ops/redis \
  http://10.8.0.1:8140/ops/sessions \
  http://10.8.0.1:8130/health; do
  printf '%-38s ' "$u"
  curl -s --max-time 4 "$u" | head -c 180 | redact || echo FAIL
  echo
done
printf '%-38s ' 'mcp-bridge 10.8.0.1:8131'
ss -ltnp | grep -q '10.8.0.1:8131' && echo 'LISTEN' || echo 'NOT_LISTENING'

line "POKER DB"
cd /opt/apps/poker-bot 2>/dev/null || { echo 'poker app missing'; exit 0; }
python3 - <<'PY' 2>/dev/null || true
from pathlib import Path
import sqlite3
p=Path('pokerbot_stage.db')
print('db_exists:', p.exists(), 'bytes:', p.stat().st_size if p.exists() else 0)
if p.exists():
    con=sqlite3.connect(p); cur=con.cursor()
    print('integrity:', cur.execute('PRAGMA integrity_check;').fetchone()[0])
    for t in ['users','platform_identities','chats','chat_memberships','score_ledger','settings','achievements','user_achievements','admin_audit_log']:
        try: print(f'{t}:', cur.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0])
        except Exception: pass
    con.close()
PY

line "GIT"
if [ -d /opt/repos/poker-bot/.git ]; then
  cd /opt/repos/poker-bot
  git status --short | sed -n '1,12p'
  git log --oneline -5
fi

line "BACKUPS"
ls -lh /opt/backups/poker-bot 2>/dev/null | tail -6 || echo 'no backups dir'

line "RECENT SIGNALS"
journalctl -u poker-bot.service --since "90 minutes ago" --no-pager 2>/dev/null \
 | grep -Ei 'error|exception|traceback|failed|warning|shutdown|started|/ops/redis|/ops/sessions' \
 | tail -25 \
 | nl -ba \
 | redact || true

echo "===== SERVER_SCREEN_DONE ====="
SH

cat > "$BIN/server-quick" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
server-screen | sed -n '1,115p'
SH

cat > "$BIN/ai-next" <<'SH'
#!/usr/bin/env bash
cat <<'TXT'
===== NEXT 10 STEPS =====
1. server-quick must be green.
2. Telegram UX: edit existing messages, no duplicate card-selection spam.
3. Duel correctness: participant-only buttons, 5 minute TTL, accept/decline/ready.
4. Telegram owner admin commands.
5. Group-admin commands: reset group, limits, group top settings.
6. Admin API/web skeleton: users, chats, scores, rules, logs, backups.
7. MAX adapter over same game core.
8. Mini App shell: profile, ratings, achievements, rooms.
9. PostgreSQL migration before public launch.
10. Domain + HTTPS + webhooks + token rotation.
TXT
SH

chmod 700 "$BIN/ai-stage" "$BIN/ai-stage-tail" "$BIN/server-screen" "$BIN/server-quick" "$BIN/ai-next"

grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"

cat >> "$CTX/notes.md" <<EOF

## $(date -u +%Y-%m-%dT%H:%M:%SZ)
Installed AI workbench stage 3: ai-stage runner with logs, fixed server-screen AI endpoint from MCP /health false check to ai-agent-api /health plus MCP port LISTEN check.
EOF

server-quick
ai-next

echo "AI_WORKBENCH_STAGE3_DONE"
