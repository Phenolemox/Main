#!/usr/bin/env bash
set -euo pipefail

BIN="$HOME/bin"
CTX="/opt/data/ai-control-room/server"
mkdir -p "$BIN" "$CTX" /opt/logs /opt/data/ai-control-room/reports

echo "===== AI SERVER WORKBENCH STAGE 4: GIT PARITY ====="
echo "host=$(hostname) user=$(whoami) time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$BIN/ai-sync-check" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
REPO="/opt/repos/poker-bot"
APP="/opt/apps/poker-bot"

echo "===== AI SYNC CHECK ====="
printf 'host: '; hostname
printf 'time: '; date -u +%Y-%m-%dT%H:%M:%SZ

if [ ! -d "$REPO/.git" ]; then
  echo "REPO_MISSING_OR_NOT_GIT=$REPO"
  echo "AI_SYNC_CHECK_DONE"
  exit 2
fi

echo
printf '%s\n' "----- REPO $REPO -----"
git -C "$REPO" fetch origin main --quiet
repo_full=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo NO_REPO_HEAD)
origin_full=$(git -C "$REPO" rev-parse origin/main 2>/dev/null || echo NO_ORIGIN_MAIN)
echo "repo_head=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo NO_REPO_HEAD)"
echo "origin_main=$(git -C "$REPO" rev-parse --short origin/main 2>/dev/null || echo NO_ORIGIN_MAIN)"
git -C "$REPO" status --short | sed -n '1,20p'
git -C "$REPO" log --oneline -5

echo
printf '%s\n' "----- APP $APP -----"
app_full="APP_NOT_GIT"
if git -C "$APP" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  app_full=$(git -C "$APP" rev-parse HEAD 2>/dev/null || echo NO_APP_HEAD)
  echo "app_head=$(git -C "$APP" rev-parse --short HEAD 2>/dev/null || echo NO_APP_HEAD)"
  git -C "$APP" status --short | sed -n '1,20p'
  git -C "$APP" log --oneline -5
else
  echo "APP_DIR_NOT_GIT"
  echo "repo/app dry-run diff, secrets and runtime files excluded:"
  rsync -ani --delete \
    --exclude='.git/' \
    --exclude='.venv/' \
    --exclude='__pycache__/' \
    --exclude='.pytest_cache/' \
    --exclude='.env' \
    --exclude='*.db' \
    --exclude='*.sqlite' \
    --exclude='*.sqlite.gz' \
    "$REPO/" "$APP/" | head -80
fi

echo
printf '%s\n' "----- SERVICE poker-bot.service -----"
main_pid=$(systemctl show poker-bot.service -p MainPID --value 2>/dev/null)
exec_start=$(systemctl show poker-bot.service -p ExecStart --value 2>/dev/null)
echo "MainPID=${main_pid:-unknown}"
echo "ExecStart=${exec_start:-unknown}" | redact
if [ -n "$main_pid" ] && [ "$main_pid" != "0" ] && [ -r "/proc/$main_pid/cmdline" ]; then
  printf 'Cmdline='; tr '\0' ' ' < "/proc/$main_pid/cmdline" | redact; echo
fi

echo
printf '%s\n' "----- HEALTH -----"
curl -s --max-time 5 http://10.8.0.1:8140/health | redact; echo
curl -s --max-time 5 http://10.8.0.1:8140/ready | redact; echo

repo_origin_ok=0
app_repo_ok=0
service_path_ok=0
[ "$repo_full" = "$origin_full" ] && repo_origin_ok=1
[ "$app_full" = "$repo_full" ] && app_repo_ok=1
echo "$exec_start" | grep -q '/opt/apps/poker-bot' && service_path_ok=1

echo
printf '%s\n' "----- RESULT -----"
[ "$repo_origin_ok" = "1" ] && echo "REPO_ORIGIN_SYNC_OK" || echo "REPO_ORIGIN_SYNC_FAIL"
if [ "$app_full" = "APP_NOT_GIT" ]; then
  echo "APP_REPO_SYNC_CHECK_NEEDED"
else
  [ "$app_repo_ok" = "1" ] && echo "APP_REPO_SYNC_OK" || echo "APP_REPO_SYNC_FAIL"
fi
[ "$service_path_ok" = "1" ] && echo "SERVICE_APP_PATH_OK" || echo "SERVICE_APP_PATH_CHECK_NEEDED"

if [ "$repo_origin_ok" = "1" ] && { [ "$app_repo_ok" = "1" ] || [ "$app_full" = "APP_NOT_GIT" ]; } && [ "$service_path_ok" = "1" ]; then
  echo "AI_SYNC_GREEN"
else
  echo "AI_SYNC_RED"
fi

echo "AI_SYNC_CHECK_DONE"
SH

cat > "$BIN/ai-preflight-poker" <<'SH'
#!/usr/bin/env bash
set +e
export PATH="$HOME/bin:$PATH"
echo "===== PREFLIGHT: SERVER QUICK ====="
server-quick
echo
echo "===== PREFLIGHT: PROJECT MEMORY ====="
ai-refresh-poker | tail -20
echo
echo "===== PREFLIGHT: QA POKER ====="
qa-poker | tail -80
echo
echo "===== PREFLIGHT: GIT/SERVER PARITY ====="
ai-sync-check
echo "AI_PREFLIGHT_POKER_DONE"
SH

chmod 700 "$BIN/ai-sync-check" "$BIN/ai-preflight-poker"

grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"

cat >> "$CTX/notes.md" <<EOF

## $(date -u +%Y-%m-%dT%H:%M:%SZ)
Installed AI workbench stage 4: ai-sync-check validates GitHub origin/main, /opt/repos/poker-bot, /opt/apps/poker-bot, poker-bot.service path and health before product stages. ai-preflight-poker chains server quick, project memory, QA and sync parity.
EOF

ai-sync-check

echo "AI_WORKBENCH_STAGE4_GIT_PARITY_DONE"
