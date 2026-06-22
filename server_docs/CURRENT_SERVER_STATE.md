# Current AI Server State

Updated from live SSH and API checks on 2026-06-22.

## Runtime

- Server label: `ai-server-amsterdam-01`
- Hostname: `8412647-yx440184.twc1.net`
- Public SSH: `5.129.229.170`
- Internal address: `10.8.0.1`
- OS: Ubuntu 24.04.4 LTS
- CPU/RAM: 4 cores, about 8 GB RAM
- Disk: 77 GB root volume, about 13% used at audit time
- Load: low at audit time

## Control Services

- `ai-agent-api.service`: active, `http://10.8.0.1:8130/health` OK
- `ai-mcp-bridge.service`: active on `10.8.0.1:8131`
- Netdata: active on `10.8.0.1:19999`, no warning or critical alarms at audit time
- GitHub CLI: logged in as `Phenolemox`, scopes include `repo` and `workflow`

## Poker Bot

- Service: `poker-bot.service`
- Repo: `/opt/repos/poker-bot`
- App: `/opt/apps/poker-bot`
- Current commit: `db34a7e Refactor Telegram poker bot to v3 modular UI`
- Health: OK
- Ready: OK
- Telegram polling: active
- Telegram bot username: `mypokerbotofficial_bot`
- Telegram commands: updated after Stage26
- QA: `poker-qa` OK, `12 passed`

## Dedicated Redis For Poker Bot

- Service: `poker-redis.service`
- Address: `127.0.0.1:6380` and `10.8.0.1:6380`
- Session endpoint after Stage26: Redis OK, classic/pending/duel sessions empty

## Database And Backups

- Current poker bot DB: SQLite in the deployed app directory
- Backups root: `/opt/backups`
- Server backup timer: `ai-server-backup.timer`, daily at 04:30 UTC

## Current Yellow Points

- Public domain/TLS routing is not finalized.
- Control-room web UI is not finished.
- MCP bridge is active, but its HTTP health check needs a documented endpoint or command-level check.
- Poker bot still uses SQLite; PostgreSQL should be the production target before broad public launch.
- `Phenolemox/Main` contains many historical stage folders. They are retained for audit, but active work should use the current folders only.

## Working Rules

- Prefer live server state over old chat history.
- Use `server-quick`, `ai-sync-check`, `ai-repo-check`, `poker-qa` and `telegram-bot-check` before claims of completion.
- Do not print or commit secrets.
- Keep server as the product; keep bots as managed projects.
