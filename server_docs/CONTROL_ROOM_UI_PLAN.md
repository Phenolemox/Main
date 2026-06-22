# Control Room UI Plan

## Current Reality

The server already has useful panels:

- Homepage Dashboard on `10.8.0.1:3010`
- Gatus on `10.8.0.1:3001`
- Netdata on `10.8.0.1:19999`
- Dozzle on `10.8.0.1:8082`
- Adminer on `10.8.0.1:8081`
- Portainer on `10.8.0.1:9443`
- Code Server on `10.8.0.1:8080`

Stage3 custom UI is now deployed:

- App path: `/opt/apps/ai-control-room`
- Service: `ai-control-room.service`
- Private URL: `http://10.8.0.1:8150`
- Health: `/health`
- Main summary API: `/api/summary`
- Bot registry API: `/api/bots`
- Poker Admin API: `/api/poker-admin`
- Write actions: guarded by `CONTROL_ROOM_TOKEN`
- Poker Admin bridge: guarded by `CONTROL_ROOM_TOKEN` and server-side `POKER_ADMIN_TOKEN`

## Product Direction

Build a custom admin cockpit that does not replace specialized tools. It should aggregate status and actions:

- service registry and health;
- GitHub/app sync;
- deploy and rollback actions;
- logs by service;
- backup status and manual backup trigger;
- bot registry;
- poker-bot admin drill-down;
- links to Homepage, Gatus, Netdata, Dozzle, Adminer, Portainer and Code Server.

## Stage3 Version

Implemented as a FastAPI backend plus a dense web UI:

- backend reads from systemd, health endpoints, Git state, filesystem state and known service manifests;
- frontend shows server state, services, bot registry, GitHub/app state, health endpoints, backups, logs and panel links;
- Poker Admin drill-down shows bot summary, users with score totals and today's attempts, attempts table, leaderboards, settings editor and audit log;
- Poker Admin actions can adjust/reset scores, grant/reset attempts and block/unblock users through the bot Admin API;
- write actions require token auth and confirmation;
- no secrets are displayed;
- domain should be `admin.<user-domain>` after TLS is configured.

Next build should add a proper login screen, richer bot registry metadata, MAX status and a public domain/TLS route.

## Poker Bot Drill-Down

The poker page should include:

- health and Telegram status;
- active sessions;
- daily attempts from durable `attempt_ledger`;
- top score and top duel;
- rule/settings JSON editor;
- user score adjustment;
- attempts grant/reset;
- reset actions with audit log;
- block/unblock users;
- Mini App URL and MAX App URL status; still pending public domain/TLS.

## Domain/TLS Decision

Use one owned domain and create subdomains:

- `admin.<domain>` for control room;
- `poker.<domain>` for poker landing and Telegram Mini App;
- `api.<domain>` for public API edge if needed.

TLS should be issued for the chosen domain. Reusing another site's certificate is only valid if the new hostname is included in that certificate.
