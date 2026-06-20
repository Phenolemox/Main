# AI Server Operating Rules

## Source of truth

GitHub and live server checks are the source of truth. Chat memory is useful, but it is not trusted when it conflicts with repository docs or current server state.

Before meaningful work, refresh context with:

```bash
server-context
server-ops
server-audit
```

## Terminal model

Termius is only the SSH/SFTP client. It is not the AI itself. The AI layer is the controlled command set on the server: `ai-state`, `ai-logs`, `ai-deploy-git`, `ai-env`, `server-*`, and project-specific helpers such as `poker-*`.

## Output readability

Use numbered output when diagnosing logs or files:

```bash
server-logs poker-bot.service "2 hours ago"
server-tail poker-bot.service
nl -ba file.py | sed -n '1,220p'
```

Not every raw shell command is numbered by default. Numbering is applied by helper commands where it is useful.

## Safety rules

- Never commit `.env`, tokens, private keys, passwords, SQLite databases, backups, archives, or dumps.
- Never print secrets in normal logs.
- Redact bot tokens, Redis URLs, passwords, secret keys and long credential-looking values in diagnostics.
- Do not expose admin panels publicly without HTTPS, authentication, and explicit approval.
- Do not delete services, data, backups, or unknown artifacts without explicit confirmation.
- Unknown leftovers should be audited and quarantined before deletion.

## Deployment standard

Every deploy must follow the controlled chain:

1. Pull latest GitHub state.
2. Apply changes.
3. Run Python compile checks.
4. Run tests.
5. Commit.
6. Push.
7. Deploy with `ai-deploy-git`.
8. Check `/health`.
9. Check `/ready`.
10. Check redacted logs.

## Architecture direction

- GitHub is code truth.
- Server is runtime truth.
- SQLite is stage database only.
- PostgreSQL is the production database target.
- Redis is required for active game sessions, duel state and rate limits.
- Telegram and MAX must be adapters over one shared game core.
- Admin controls must write audit logs.
- Backups must stay outside Git.

## Current project priority

For poker-bot, do not continue large game refactors until Redis authentication is resolved or a dedicated Redis instance is installed. `/ops/redis` must be green before moving active sessions to Redis.
