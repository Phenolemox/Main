# Fast Path

Current baseline:
- tmux session ai is the working shell.
- poker-bot runs on 10.8.0.1:8140.
- dedicated poker Redis runs on 10.8.0.1:6380.
- health, ready, redis and sessions checks are green.
- GitHub origin/main, /opt/repos/poker-bot, /opt/apps/poker-bot and poker-bot.service must stay in sync.
- ai-sync-check is the mandatory parity preflight before each product stage.
- safe devtools installer is canonical.
- old devtools installers redirect to the safe installer.

Next sequence:
1. Run final server check plus Git/server parity preflight.
2. Clean Telegram UX.
3. Fix duel flow and participant-only buttons.
4. Add owner admin commands.
5. Add group-admin commands: reset group, limits, group top settings.
6. Add private admin web panel skeleton.
7. Add MAX adapter over the same game core.
8. Add Mini App shell.
9. Move production database from SQLite to PostgreSQL before public launch.
10. Add domain and HTTPS before webhook mode.
