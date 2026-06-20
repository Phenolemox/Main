# AI Control Room / Server model

## What Termius is

Termius is only the SSH/SFTP client. It is not an AI by itself. Tabs mean different execution places:

- SSH tab `ai-server-amsterdam-01`: remote Ubuntu server shell.
- SFTP tab: file browser for the remote server.
- Local Terminal: Windows PowerShell on the local PC, not the server.
- Serial tab: irrelevant for this server workflow.

## What the AI layer is

The AI layer lives on the server as controlled commands and services:

- `ai-state` shows current server/project state.
- `ai-logs` reads redacted service logs.
- `ai-deploy-git` deploys a GitHub repository as a systemd service.
- `ai-env` inspects env keys without printing secret values.
- `ai-context` and project markdown files preserve project memory.
- `ai-agent-api` exposes controlled server tools over the VPN API.
- `ai-mcp-bridge` is the bridge for future external AI tools.

This does not turn the shell prompt into natural-language ChatGPT. It gives AI systems safe, limited tools around server state, logs, deploys, env checks and project context.

## Why not give free shell to every AI

Free shell access is dangerous. A broken command can delete services, expose tokens, print secrets, or corrupt data. The correct model is controlled tools:

- read state;
- inspect redacted logs;
- deploy from Git;
- check env key names only;
- run tests;
- backup before risky changes;
- ask for confirmation before destructive operations.

## Current workflow

1. ChatGPT writes code or installers to GitHub.
2. User runs one short command in the SSH tab.
3. Server pulls from GitHub.
4. Tests run.
5. Service deploys with `ai-deploy-git`.
6. Health/ready/log checks confirm state.
7. Project memory is updated in GitHub docs.

This is already close to one-button deploy. Full automation can be added later through GitHub Actions/webhooks, but only after secrets, domains, and rollback strategy are clean.

## Self-healing model

Safe stages:

1. Observe: healthguard checks health/ready and logs status.
2. Backup: database backup before recovery actions.
3. Restart: only after repeated health failures.
4. Redis sessions: active games survive app restarts.
5. PostgreSQL: production-grade database.
6. Metrics/admin: visibility and manual control.

Never allow automatic code rewrites or schema changes directly in production without a Git commit, tests, backup, and owner approval.

## Poker bot architecture direction

- GitHub is the source of code truth.
- Server is the runtime.
- SQLite is current stage database.
- Redis will hold active sessions and duel state.
- PostgreSQL will replace SQLite for production.
- Telegram and MAX are adapters.
- Game Core is shared and platform-neutral.
- Admin panel controls rules, scores, chats, logs and broadcasts.

## Memory rule

Important decisions must be written to repository markdown, especially:

- `pokerbot_memory/PROJECT_STATE.md`
- `pokerbot_docs/production_master_plan.md`
- `pokerbot_docs/AI_CONTROL_ROOM_MODEL.md`

Future chats should start by reading these files before making changes.
