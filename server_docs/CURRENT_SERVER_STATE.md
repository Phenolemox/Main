# Current AI Server State

Updated from live SSH and API checks on 2026-06-23.

## Runtime

- Server label: `ai-server-amsterdam-01`
- Hostname: `8412647-yx440184.twc1.net`
- Public SSH: `5.129.229.170`
- Internal address: `10.8.0.1`
- OS: Ubuntu 24.04 LTS
- All bot/control services bind to the internal VPN address `10.8.0.1` (not public).

## Control Services

- `ai-agent-api.service`: active, `http://10.8.0.1:8130/health` OK
- `ai-mcp-bridge.service`: active on `10.8.0.1:8090` (FastMCP, transport `streamable-http`, endpoint `/mcp`)
- `ai-control-room.service`: active, `http://10.8.0.1:8150/health` OK, `write_actions_configured: true`, `poker_admin_configured: true`
- `bots-hub.service`: active, `http://10.8.0.1:8170/health` OK
- Caddy: installed (2.6.2), placeholder mode. Run `sudo bots-set-domain <domain>` to enable public HTTPS for all subdomains.
- GitHub CLI: logged in as `Phenolemox`, scopes include `repo` and `workflow`

## Bots (status 2026-06-23)

- poker-bot `:8140` — healthy, `mypokerbotofficial_bot`, commit `8dd2c59`, `poker-qa` 13 passed.
- cb-balloons-bot `:8160` — healthy, `@CB_Balloonsbot` (Мастер сфер). `/start` FIXED.
- autobot-bot `:8161` — healthy, `@Inspectorauto_bot` (Инспектор). `/start` FIXED.

### /start fix (CB Balloons + Autobot)

Root cause: `TELEGRAM_MINI_APP_URL=http://10.8.0.1:8160/miniapp` (non-HTTPS, private IP) was used to
build a Telegram `WebApp` inline button. Telegram rejects `sendMessage` with
`Bad Request: ... Web App URL ... is invalid: Only HTTPS links are allowed`, so `/start` produced no
reply while other commands (which do not use that button) worked. Fix: `_app_keyboard()` only emits a
WebApp/url button for valid public HTTPS URLs, and `start` falls back to a plain reply on any markup
error. Verified live: bad payload returns 400, fixed payload returns ok=true.

### Poker UX changes (commit 8dd2c59)

- Card buttons render rank+suit first (colored, readable; fixes `10...` truncation).
- Leaderboards use distinct icons: 🌍 game-world, 🏠 game-chat, 🗡 duel-world, 🛡 duel-chat.
- Profile button "Сменить ник" with hint that points/stats are kept.
- New `/rules` command + button (rules text + combinations and points).
- Buy an extra attempt for 10 points when the daily limit is reached (private base 5, chat base 1, unlimited purchases).
- Admin: reset attempts separately for chat/world in Telegram (boss/admin) and via `/admin/attempts/reset` API (used by Control Room).
- Duel: blue/yellow diamonds next to nicks swapped.

## Repositories (pushed to GitHub)

- `Phenolemox/poker-bot` @ `8dd2c59` (poker UX changes)
- `Phenolemox/Main` @ `fec98a9` (bots platform sources + /start fix + interactive Control Room)

## Domain / TLS (pending user input)

- Caddy installed; `bots-set-domain` helper generates reverse-proxy + Mini App HTTPS config and restarts bots.
- Required once a domain is chosen — create DNS A records (all → `5.129.229.170`):
  `admin.<domain>`, `bots.<domain>`, `poker.<domain>`, `balloons.<domain>`, `autobot.<domain>`.
- Then run: `sudo bots-set-domain <domain>`.
- Subdomain → service map: admin→8150, bots→8170, poker→8140, balloons→8160, autobot→8161.

## MCP (Cursor) connection

- Endpoint: `http://10.8.0.1:8090/mcp` (reachable over the WireGuard VPN `10.8.0.0/24`).
- Tools: get_health, get_state, get_state_summary, refresh_state, list_projects, get_status,
  get_logs, get_service_status, create_task, deploy_git, env_check, env_keys.

## Current Yellow Points

- Public domain/TLS not live yet: requires the user to pick a domain and create DNS records (see above).
- MAX webhooks/Mini App registration in BotFather require the public HTTPS URLs to exist first.
- Poker bot still uses SQLite; PostgreSQL is the production target before broad public launch.
- Exposing the MCP bridge publicly is not recommended without an auth layer; use the VPN.

## Working Rules

- Prefer live server state over old chat history.
- Use `server-quick`, `poker-qa` before claims of completion.
- Do not print or commit secrets. Tokens live only in `/opt/secrets/bots-platform.env` and app `.env` files.
