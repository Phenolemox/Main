# AI Server Control Room

This repository is the public control and handoff layer for the AI server and its deployable projects.

Current primary server:

- Host: `ai-server-amsterdam-01`
- SSH host: `5.129.229.170`
- Internal API network: `10.8.0.1`
- Main control API: `ai-agent-api` on `10.8.0.1:8130`
- MCP bridge: `ai-mcp-bridge` on `10.8.0.1:8131`
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

## Active Repositories

- `Phenolemox/Main`: control scripts, server docs, handoff docs, stage installers and reference assets.
- `Phenolemox/poker-bot`: production source for the Telegram poker bot.

## Current Poker Bot State

- Latest deployed commit: `db34a7e Refactor Telegram poker bot to v3 modular UI`
- QA: `py_compile` OK, `pytest` OK, `12 passed`
- Telegram bot: `mypokerbotofficial_bot`
- Telegram polling: active
- Redis sessions: active and empty after Stage26 reset

## Current Structure

- `server_docs/`: server architecture, live state, operations and safety rules.
- `pokerbot_docs/`: poker bot product and service instructions.
- `server_codex_bootstrap_stage1/`: one-command bootstrap for server tools, GitHub sync and Codex SSH access.
- `pokerbot_v3_clean_stage26_linux/`: Linux-safe Stage26 installer for the modular poker bot.
- `reference/screenshots/pokerbot/`: UI screenshots used as product reference.
- Old `pokerbot_stage*` folders are historical installers. They are retained for audit only; new work should use the active folders above.

## Required Operating Rule

Do not treat the poker bot as the whole server. The server is the main product: it must be able to host several bots, sites, Mini Apps, admin panels and APIs with consistent logging, backups, monitoring, GitHub sync and deploy controls.
