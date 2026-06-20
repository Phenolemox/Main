# Architecture

```text
Telegram / MAX
    ↓ HTTPS webhook
public reverse proxy :443
    ↓ internal
poker-bot FastAPI :8140
    ↓
PostgreSQL + Redis
```

## Modules

```text
app/main.py                 FastAPI entrypoint
app/api/health.py           health/readiness
app/api/webhooks.py         Telegram/MAX webhook entrypoints
app/api/miniapp.py          Mini App API
app/api/admin.py            internal admin API
app/core/config.py          settings
app/core/security.py        signature helpers
app/game/cards.py           poker engine
app/game/scoring.py         duel scoring
app/game/achievements.py    achievement registry
```

## Planned data model

```text
users
platform_identities
chats
chat_memberships
game_sessions
duels
score_ledger
rating_snapshots
achievements
user_achievements
bans
admin_audit_log
```
