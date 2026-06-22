# Operations Runbook

## Daily Checks

```bash
server-quick
ai-sync-check
telegram-bot-check
bots-list
```

Expected:

- server load is low;
- disk has enough free space;
- `poker-bot.service` is active;
- `/health` and `/ready` are OK;
- repo, app and GitHub commit are aligned.

## Deploy Poker Bot

```bash
poker-qa
poker-deploy
ai-sync-check
```

For the current v3 installer:

```bash
poker-stage26
```

Successful marker:

```text
POKER_V3_CLEAN_STAGE26_DONE
```

## Read Logs

```bash
journalctl -u poker-bot.service --since "15 minutes ago" --no-pager
ai-tail 120
```

## Telegram Checks

```bash
telegram-bot-check
telegram-set-commands
```

`telegram-set-commands` is safe to rerun after command changes.

## Server Health

```bash
curl -s http://10.8.0.1:8130/health
curl -s http://10.8.0.1:8140/health
curl -s http://10.8.0.1:19999/api/v1/info | jq '.alarms'
ai-mcp-check
```

## GitHub Sync

```bash
ai-repo-check
git -C /opt/repos/Main status --short
git -C /opt/repos/poker-bot status --short
git -C /opt/apps/poker-bot status --short
```

## Recovery

1. Check health and logs.
2. If a deployment failed, inspect `ai-tail 160`.
3. If code is bad, redeploy the last known good Git commit.
4. If sessions are stuck, run `poker-reset-sessions`.
5. If database is damaged, restore from `/opt/backups`.

## Backup Now

```bash
ai-backup-now
```

Expected marker:

```text
AI_BACKUP_NOW_DONE
```

Never paste full `.env` files into chat or GitHub.
