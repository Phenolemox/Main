# AI Server Control Room

This repository is the public control and handoff layer for the AI server and its deployable projects.

Current primary server:

- Host: `ai-server-amsterdam-01`
- SSH host: `5.129.229.170`
- Internal API network: `10.8.0.1`
- Main control API: `ai-agent-api` on `10.8.0.1:8130`
- MCP bridge: `ai-mcp-bridge` on `10.8.0.1:8131`
- Custom control room: `ai-control-room` on `10.8.0.1:8150`
- Poker bot API: `poker-bot` on `10.8.0.1:8140`
- Monitoring: Netdata on `10.8.0.1:19999`

## Active Commands

Run on the server as `admin`:

```bash
server-quick
ai-sync-check
ai-repo-check
poker-qa
poker-deploy
poker-stage26
telegram-bot-check
telegram-set-commands
bots-list
ai-mcp-check
ai-backup-now
```

Open the custom control room through a private tunnel from a local terminal:

```bash
ssh -i .codex_ai_server_ed25519 -L 8150:10.8.0.1:8150 admin@5.129.229.170
```

Then visit `http://127.0.0.1:8150`. Read-only server status works without login. Server actions and Poker Admin require a Control Room session created with `CONTROL_ROOM_TOKEN` from `/opt/apps/ai-control-room/.env`. Automation can still use the `X-Control-Room-Token` header. Poker Admin connects to the bot through server-side `POKER_ADMIN_TOKEN`.

## Active Repositories

- `Phenolemox/Main`: control scripts, server docs, handoff docs, stage installers and reference assets.
- `Phenolemox/poker-bot`: production source for the Telegram poker bot.

## Current Poker Bot State

- Latest deployed commit: `3f10729 Document attempt ledger operations`
- QA: `py_compile` OK, `pytest` OK, `13 passed`
- Telegram bot: `mypokerbotofficial_bot`
- Telegram polling: active
- Admin API: summary, users with scores and daily attempts, chats, settings, leaderboards, audit, score adjust, score reset, attempts grant/reset and block/unblock
- Redis sessions: active

## Current Structure

- `server_docs/`: server architecture, live state, operations and safety rules.
- `pokerbot_docs/`: poker bot product and service instructions.
- `server_codex_bootstrap_stage1/`: one-command bootstrap for server tools, GitHub sync and Codex SSH access.
- `ai_control_room_app/`: custom FastAPI control-room UI for services, health, bot registry, Poker Admin, GitHub/app state, backups, logs and safe server actions.
- `ai_control_room_stage1/`: installer for `/opt/apps/ai-control-room` and `ai-control-room.service`.
- `pokerbot_v3_clean_stage26_linux/`: Linux-safe Stage26 installer for the modular poker bot.
- `reference/screenshots/pokerbot/`: UI screenshots used as product reference.
- Old `pokerbot_stage*` folders are historical installers. They are retained for audit only; new work should use the active folders above.

## Required Operating Rule

Do not treat the poker bot as the whole server. The server is the main product: it must be able to host several bots, sites, Mini Apps, admin panels and APIs with consistent logging, backups, monitoring, GitHub sync and deploy controls.
