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

`/opt/apps/ai-control-room` is currently documentation, not a custom app.

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

## First Version

Use a FastAPI backend plus a dense web UI:

- backend reads from `ai-agent-api`, systemd, GitHub status and known service manifests;
- frontend shows server state, bot cards, deploy state, backups and logs;
- write actions require auth and confirmation;
- no secrets are displayed;
- domain should be `admin.<user-domain>` after TLS is configured.

## Poker Bot Drill-Down

The poker page should include:

- health and Telegram status;
- active sessions;
- daily attempts;
- top score and top duel;
- rule text editor;
- user score/attempt adjustment;
- reset actions with audit log;
- Mini App URL and MAX App URL status.

## Domain/TLS Decision

Use one owned domain and create subdomains:

- `admin.<domain>` for control room;
- `poker.<domain>` for poker landing and Telegram Mini App;
- `api.<domain>` for public API edge if needed.

TLS should be issued for the chosen domain. Reusing another site's certificate is only valid if the new hostname is included in that certificate.
