# Current AI Server State

Updated from live server output after Redis and kernel stages.

## Runtime

- Server: ai-server-amsterdam-01
- Main runtime address: 10.8.0.1
- poker-bot: active/running
- ai-agent-api: healthy
- ai-mcp-bridge: active on 10.8.0.1:8131
- Docker: active

## poker-bot

- Service: poker-bot.service
- Health: OK
- Ready: OK
- Telegram polling: true
- Runtime version reported by API: 0.8.0
- systemd restarts: 0 after current stage
- LimitNOFILE: 65535

## Dedicated Redis for poker-bot

- Service: poker-redis.service
- Address: 10.8.0.1:6380 and 127.0.0.1:6380
- Auth: enabled
- /ops/redis: OK
- Last observed latency: about 1.37 ms
- Last observed used memory: about 941.84 KB
- vm.overcommit_memory: 1
- LimitNOFILE: 65535

## Database and backups

- Current stage DB: SQLite at /opt/apps/poker-bot/pokerbot_stage.db
- Integrity: OK
- Backups: /opt/backups/poker-bot
- Hourly backup cron installed

## Kernel/runtime tuning applied

- vm.overcommit_memory = 1
- net.core.somaxconn = 1024
- net.ipv4.tcp_max_syn_backlog = 4096
- vm.swappiness = 10
- fs.file-max = 1048576

## Current red/yellow points

- SQLite is still stage-only. PostgreSQL remains the production target before broad public launch.
- Active poker game sessions still need to be moved to Redis.
- Telegram token should be rotated before public launch because it appeared during setup screenshots.
- Admin panel and group-admin controls still need to be built.
- MAX adapter and Mini App remain next large product layers.

## Working rules

- Use tmux session `ai` for long commands.
- Use `server-ops`, `server-logs`, `server-context`, `server-audit` for diagnostics.
- Do not trust old chat memory over live server state and GitHub docs.
- Do not print or commit secrets.
