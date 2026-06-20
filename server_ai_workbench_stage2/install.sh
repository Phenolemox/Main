#!/usr/bin/env bash
set -euo pipefail

BIN="$HOME/bin"
CTX="/opt/data/ai-control-room/server"
REPORTS="/opt/data/ai-control-room/reports"
mkdir -p "$BIN" "$CTX" "$REPORTS"

echo "===== AI SERVER WORKBENCH STAGE 2 ====="
echo "host=$(hostname) user=$(whoami) time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$BIN/redact" <<'SH'
#!/usr/bin/env bash
sed -E \
  -e 's#bot[0-9]+:[A-Za-z0-9_-]+#bot[REDACTED]#g' \
  -e 's#redis://:[^@]+@#redis://:[REDACTED]@#g' \
  -e 's#(TOKEN|SECRET|PASSWORD|KEY)=?[^ ]+#\1_REDACTED#g' \
  -e 's#([A-Za-z0-9_-]{20,})#\1#g'
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
  http://10.8.0.1:8131/health; do
  printf '%-38s ' "$u"
  curl -s --max-time 4 "$u" | head -c 180 | redact || echo FAIL
  echo
done

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

cat > "$BIN/server-logscreen" <<'SH'
#!/usr/bin/env bash
set +e
svc="${1:-poker-bot.service}"
since="${2:-90 minutes ago}"
journalctl -u "$svc" --since "$since" --no-pager 2>/dev/null \
 | grep -Ei 'error|exception|traceback|failed|warning|shutdown|started|health|ready|ops/redis|ops/sessions|getUpdates|callback|duel|cards|telegram' \
 | tail -70 \
 | nl -ba \
 | redact
SH

cat > "$BIN/server-quick" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
server-screen | sed -n '1,115p'
SH

cat > "$BIN/ai-refresh-poker" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
mkdir -p /opt/data/ai-control-room/projects/poker-bot /opt/data/ai-control-room/history
TS=$(date -u +%Y%m%d-%H%M%S)
OUT="/opt/data/ai-control-room/projects/poker-bot/PROJECT_STATE.md"
{
  echo "# Poker Bot Project State"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Server quick state"
  server-screen | sed -n '1,115p'
  echo
  echo "## Repo"
  cd /opt/repos/poker-bot 2>/dev/null && git status --short && git log --oneline -12
  echo
  echo "## Fast path"
  curl -fsSL https://raw.githubusercontent.com/Phenolemox/Main/main/server_docs/FAST_PATH.md 2>/dev/null | sed -n '1,160p'
} | redact > "$OUT"
cp "$OUT" "/opt/data/ai-control-room/history/poker-state-$TS.md"
echo "POKER_MEMORY_REFRESHED: $OUT"
SH

cat > "$BIN/ai-note" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /opt/data/ai-control-room/server
note="$*"
[ -n "$note" ] || { echo 'Usage: ai-note text'; exit 1; }
{
  echo
  echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$note"
} >> /opt/data/ai-control-room/server/notes.md
echo "AI_NOTE_SAVED"
SH

cat > "$BIN/ai-runbook" <<'SH'
#!/usr/bin/env bash
cat <<'TXT'
===== AI SERVER RUNBOOK =====
1) Перед работой: ai-refresh-poker
2) Быстрый экран без простыни: server-quick
3) Логи на один экран: server-logscreen poker-bot.service "90 minutes ago"
4) Проверка кода: qa-poker | tail -80
5) Деплой только через stage-скрипт из GitHub + финальный health/ready/ops.
6) Не трогать .env, db, backups, токены. В выводах всегда redaction.
7) Старые stage не переиспользовать без редиректа на актуальный safe/stable.
8) Игровая логика: один core для Telegram, MAX и Mini App.
TXT
SH

chmod 700 "$BIN/redact" "$BIN/server-screen" "$BIN/server-logscreen" "$BIN/server-quick" "$BIN/ai-refresh-poker" "$BIN/ai-note" "$BIN/ai-runbook"

grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"

cat > "$CTX/OPERATING_RULES.md" <<'MD'
# AI Server Operating Rules

- The canonical live context is `/opt/data/ai-control-room/projects/poker-bot/PROJECT_STATE.md`.
- Before any code stage, refresh state with `ai-refresh-poker`.
- Use compact one-screen checks: `server-quick` and `server-logscreen`.
- Never print secrets. Use `redact` for logs and reports.
- Do not reuse deprecated stage paths unless they redirect to the safe current version.
- Keep Telegram, MAX and Mini App on one shared game core.
- Runtime game state belongs in Redis; persistent identity/scores/settings belong in DB.
- SQLite is OK for test/stage; PostgreSQL is required before broad public launch.
- Every stage must end with health, ready, redis/session checks and a unique DONE marker.
MD

ai-refresh-poker | sed -n '1,20p'
server-quick

echo "AI_WORKBENCH_STAGE2_DONE"
