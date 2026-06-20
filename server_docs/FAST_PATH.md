# Fast Path

Current baseline:
- tmux session ai is the working shell.
- poker-bot runs on 10.8.0.1:8140.
- dedicated poker Redis runs on 10.8.0.1:6380.
- health, ready, redis and sessions checks are green.
- safe devtools installer is canonical.
- old devtools installers redirect to the safe installer.

Next sequence:
1. Run final server check.
2. Clean Telegram UX.
3. Fix duel flow and participant-only buttons.
4. Add owner admin commands.
5. Add private admin web panel skeleton.
6. Add MAX adapter over the same game core.
7. Add Mini App shell.
8. Move production database from SQLite to PostgreSQL before public launch.
9. Add domain and HTTPS before webhook mode.
