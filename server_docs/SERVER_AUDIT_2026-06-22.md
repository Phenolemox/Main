# Server Audit 2026-06-22

Live audit source: SSH as `admin` on `5.129.229.170`, 2026-06-22 UTC.

## Summary

The server is healthy and has enough capacity for the poker bot plus additional small bots and web apps. The main weak point is not CPU or memory; it is product structure and operational polish: old stage folders, partial historical installers, incomplete public routing/domain plan, and a control-room UI still missing.

## Hardware And OS

- OS: Ubuntu 24.04.4 LTS
- Kernel: `6.8.0-124-generic`
- CPU: 4 cores
- RAM: about 7.8 GiB
- Disk: 77 GiB root volume, 9.6 GiB used, 67 GiB available
- Load during audit: about `0.09 0.07 0.11`
- Swap: disabled

## Running Core Services

- `ai-agent-api.service`: active, health OK at `http://10.8.0.1:8130/health`
- `ai-mcp-bridge.service`: active, MCP streamable HTTP bridge on `10.8.0.1:8131`
- `poker-bot.service`: active, health OK at `http://10.8.0.1:8140/health`
- `poker-redis.service`: active on `127.0.0.1:6380` and `10.8.0.1:6380`
- `redis-server.service`: active on `6379`
- `docker.service`: active
- `zabbix-agent.service`: active
- Netdata: active on `10.8.0.1:19999`, no warning or critical alarms at audit time

## App And Repo Layout

Active paths:

- `/opt/repos/Main`
- `/opt/repos/poker-bot`
- `/opt/repos/ai-server-private-infra`
- `/opt/apps/ai-agent-api`
- `/opt/apps/ai-mcp-bridge`
- `/opt/apps/ai-control-room`
- `/opt/apps/poker-bot`
- `/opt/backups`
- `/opt/logs`

GitHub state after Stage26:

- `/opt/repos/Main`: synced to `6360dba`
- `/opt/repos/poker-bot`: synced to `db34a7e`
- `/opt/apps/poker-bot`: synced to `db34a7e`

## Poker Bot Verification

- Commit: `db34a7e Refactor Telegram poker bot to v3 modular UI`
- Deploy: OK
- `poker-qa`: OK
- Tests: `12 passed`
- Health: `{"status":"healthy","service":"poker-bot","version":"0.8.0","telegram_polling":true}`
- Ready: `{"ok":true,"db":"ready"}`
- Sessions: Redis OK, no active classic/pending/duel sessions immediately after deployment
- Telegram: `getMe` OK, username `mypokerbotofficial_bot`
- Telegram commands: updated successfully

## Backups And Timers

Observed timers:

- `ai-server-backup.timer`: daily at 04:30 UTC
- `ai-refresh.timer`: frequent server state refresh
- `server-health-check.timer`: frequent health check
- standard Ubuntu timers for apt, logrotate, fstrim and package db backup

Manual backup verified:

- `/opt/backups/ai-server-backup-2026-06-22_11-04-59.tar.gz`

Next improvement: add a manifest with checksums and explicit included/excluded paths.

## Issues To Fix Next

- Build real web admin/control-room UI over `ai-agent-api`, Netdata and project metadata.
- Add domain/TLS routing for public sites, Mini Apps and admin panels.
- Add explicit bot registry so poker-bot becomes one managed service among many.
- Add production database plan: keep SQLite only for small/internal stage, move high-traffic bot data to PostgreSQL.
- Add a visible backup inventory and restore drill.
- Add MCP health documentation; current FastMCP bridge is active but does not expose `/health`.
- Retire or archive old stage folders in `Phenolemox/Main` after confirming no active scripts depend on them.
