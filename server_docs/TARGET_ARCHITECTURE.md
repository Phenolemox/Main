# Target Architecture

## Principle

The server is the main product. Bots, Mini Apps, dashboards and websites are deployable projects managed by the server.

## Target Layout

```text
/opt
  /apps          deployed runtime copies
  /repos         Git working copies
  /data          shared runtime state, indexes and control-room snapshots
  /backups       restorable backups with manifests
  /logs          stage, deploy and audit logs
  /scripts       root-owned maintenance scripts
  /secrets       root-only secret material
```

## Project Model

Each project should have:

- one GitHub repo or a clearly named folder in a repo;
- one systemd service for long-running backend work;
- one health endpoint;
- one deploy command;
- one backup rule if it stores state;
- one owner document with tokens/domains/env variables listed by name, never by value.

## Control Room

The control room should show:

- server load, disk, memory and network;
- running services and ports;
- deploy status for each project;
- GitHub sync state for repo and app copy;
- recent logs;
- backup status and restore actions;
- bot registry;
- drill-down admin pages for each bot.

For poker-bot, the drill-down admin should manage:

- rules and score tables;
- attempts and daily limits;
- user score adjustments;
- chat/global resets;
- sessions and stuck games;
- Telegram command checks;
- Mini App and MAX App links.

## Public Routing

Use domains instead of raw ports for production.

Recommended pattern:

- `admin.<domain>`: control-room admin UI
- `api.<domain>`: authenticated API edge
- `poker.<domain>`: poker bot landing page and Mini App
- `bots.<domain>`: bot catalog/status page

TLS should be managed by Caddy or Nginx plus Certbot. Do not reuse unrelated certificates unless the domain names match the certificate SAN list.

## Security Baseline

- SSH key auth only.
- No secrets in GitHub.
- All `.env` files live only on the server.
- Internal APIs bound to `10.8.0.1` unless intentionally public.
- Public admin routes require authentication.
- Deploy tools redact tokens in logs.
- Backups exclude `.env` by default unless stored encrypted.

## Capacity

The current server has enough headroom for several small FastAPI bots/sites. Before large public launch:

- move high-write bot state to PostgreSQL;
- add queue/background job discipline for long tasks;
- add reverse proxy rate limiting;
- test backup restore;
- test restart behavior under load.
