# Poker Bot project state

## Server state

The server ai-server-amsterdam-01 runs the poker-bot service on the private VPN address 10.8.0.1:8140. Health and ready endpoints are green. SQLite integrity is OK. Backups are stored outside Git in /opt/backups/poker-bot. Secrets must stay only in .env on the server.

## Current product goal

Build a modular poker bot for Telegram and MAX, plus a mobile Mini App and admin panel. Telegram works first. MAX must reuse the same game core, not duplicate logic.

## Final game rules

### Solo game

A solo game starts with /cards. The player receives exactly five cards. There is no table in solo mode. The player may manually select zero, one, or two cards for exchange. A third selected card must be rejected. Only the owner can press hand buttons. Card selection must edit the same message, not create a new message. Final result must edit the same active message.

### Duel game

A duel works only in group chats. A player creates a challenge with /duel @username. The invite lives for five minutes. Only the target player can accept. Only participants can decline. After accept, a table appears because there is an opponent. Duel mode uses five table cards and two private cards per player. Each player sees their own private card selection view immediately. Each player can select zero, one, or two own cards. Other users cannot press those buttons. Result appears once after both players are ready.

## Telegram UX rules

Menus must be compact. Active card selection must not contain unnecessary menu buttons. Profile contains nickname settings. Public leaderboards show the game nickname, not Telegram username. Top game and top duel must be visually distinct. Group game top, global game top, group duel top, and global duel top are separate concepts.

## Admin requirements

Owner admin can see health, users, chats, scores, rules, phrases, logs, backups, and audit events. Owner can ban, unban, adjust scores, reset scores, configure limits, configure scoring, and manage announcements. Group admins can manage only their own group settings and group score resets. All admin actions must be written to audit log.

## Logging rules

Default logging should store technical events, not full raw chats. Debug logging per group can be enabled temporarily from admin panel. Logs must be redacted and limited by retention. No tokens, secrets, phone numbers, emails, or private cards should be printed in plain logs.

## Production requirements

SQLite is acceptable for stage testing. Production should move to PostgreSQL. Runtime sessions and duel state should move to Redis before multiple workers or large public launch. Backups must run automatically. Public webhooks require HTTPS and secret headers. Internal admin panels must remain private or token-protected.

## Deployment standard

Every stage must pull from GitHub, apply code, run py_compile, run tests, commit, push, deploy with ai-deploy-git, health-check, ready-check, and inspect redacted logs.
