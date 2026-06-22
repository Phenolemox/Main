# Poker Bot Service Spec

## Role

Poker-bot is one managed project on the AI server. It is not the server itself.

## Runtime

- Repo: `Phenolemox/poker-bot`
- Server repo: `/opt/repos/poker-bot`
- Deployed app: `/opt/apps/poker-bot`
- Service: `poker-bot.service`
- API: `http://10.8.0.1:8140`
- Redis sessions: `poker-redis.service` on `6380`

## Current Version

- Commit: `9cdfb0f Add durable attempt ledger admin API`
- Telegram username: `mypokerbotofficial_bot`
- Telegram mode: polling
- Attempts: durable `attempt_ledger` in SQLite, with private/chat daily scopes.

## V3 Code Structure

```text
app/bot/telegram.py       thin webhook/poller wrapper
app/bot/v3/cards.py       card rendering
app/bot/v3/keyboards.py   Telegram keyboards
app/bot/v3/router.py      command and callback routing
app/bot/v3/texts.py       user-facing copy
```

## Commands

- `/start`: main menu
- `/cards`: classic draw/exchange
- `/tops`: rating menu
- `/topscore`: game score rating
- `/topduel`: duel rating
- `/profile`: profile
- `/nick`: nickname
- `/duel @nick`: group duel
- `/admin`: admin panel

## QA Gates

```bash
cd /opt/repos/poker-bot
.venv/bin/python -m py_compile $(find app -name '*.py')
.venv/bin/python -m pytest -q
```

Expected current result:

```text
12 passed
```

## Admin API

Protected by `X-Admin-Token` when `ADMIN_TOKEN` is configured:

- `GET /admin/summary`
- `GET /admin/users`
- `GET /admin/chats`
- `GET /admin/settings`
- `GET /admin/leaderboards`
- `GET /admin/audit`
- `POST /admin/score/adjust`
- `POST /admin/score/reset`
- `GET /admin/attempts`
- `POST /admin/attempts/grant`
- `POST /admin/attempts/reset`
- `PATCH /admin/users/{user_id}/block`
- `PUT /admin/settings/{key}`

Control Room uses these endpoints through server-side `POKER_ADMIN_TOKEN`. The browser never receives `POKER_ADMIN_TOKEN`.

## Product Next Steps

- Add a real Mini App frontend and set `TELEGRAM_MINI_APP_URL`.
- Add MAX adapter and set `MAX_APP_URL`.
- Add PostgreSQL migration before broad launch.
- Add screenshot-based UX regression checklist.
