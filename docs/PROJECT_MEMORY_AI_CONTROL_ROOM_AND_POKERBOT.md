# Project Memory: AI Control Room and PokerBot

## AI Control Room goal

The server must become a simple private AI production contour where the user writes a normal text task and the system turns it into working server assets.

Target behavior:

1. User writes a plain-language task.
2. AI reads the server instructions from GitHub automatically.
3. AI understands the server structure, security rules, deployment rules and available tools.
4. AI creates folders and files on the server.
5. AI pushes safe code to GitHub.
6. AI deploys the result through systemd or Docker.
7. AI registers the app in Dashboard and Gatus.
8. AI checks logs and health.
9. AI reports the result clearly.

## Important operating principle

The user should not manually upload the server instructions to every AI chat. The canonical instructions must live in GitHub and be easy to fetch from the server or provide as a single canonical file.

## Design/reference repository idea

Create a separate private GitHub repository for design and implementation references:

- screenshots of good websites;
- UI patterns;
- landing page examples;
- beautiful app screens;
- image assets;
- brand references;
- links to useful sites;
- prompts and style guides;
- components and templates.

Purpose: when creating a website, app, bot mini app, or dashboard, AI agents should not generate primitive placeholders. They should use the reference repository to produce visually strong, polished, modern, adaptive designs.

Expected result for websites and programs:

- not a bare stub;
- clean responsive layout;
- thoughtful UI/UX;
- good typography;
- visual hierarchy;
- real sections and components;
- branded style when needed;
- working navigation and pages;
- production-oriented code structure.

## Russia/access constraint

The user may periodically work from Russia. Some services or accounts may not work from Russian locations. The server is in Amsterdam and private panels are accessed through WireGuard.

Rules:

- avoid depending on services/accounts that are unavailable from the user's current location unless VPN/server path solves it;
- do not expose tokens or private keys;
- use only connected and authorized accounts;
- private panels must stay behind WireGuard;
- public projects must use domain + HTTPS when exposed.

## PokerBot target project

Existing context: the user has a working Telegram PokerBot from earlier work. It needs a major upgrade and deployment to the new server.

Target platforms:

- Telegram bot;
- MAX bot;
- Telegram Mini App;
- future MAX mini app or web app if platform supports the required integration;
- cloud API backend;
- possible deployment integration with Amvera and domains.

Core product goal:

A fast, secure, scalable poker game bot and mini app that can support many users, many chats, and future expansion.

Expected scale:

- potentially 10,000 users;
- more than 100 chats/groups in the future;
- personal games and group games;
- global leaderboards.

Main gameplay modes:

1. Private chat classic poker mode.
   - User receives 5 cards.
   - Personal game commands and profile access.

2. Private chat Texas Hold'em mode.
   - User receives 2 cards.
   - Board mechanics according to project rules.

3. Group/channel duel mode.
   - Duels work in public/group contexts.
   - Duels do not work in private chat.
   - User cannot duel themselves.
   - Nicknames and player identity must be handled safely.

4. Telegram and MAX behavior must differ by context.
   - Telegram private chat differs from Telegram group/channel.
   - MAX private chat differs from MAX group/channel.

Data and profile requirements:

- unified database for Telegram and MAX identities;
- user profile;
- total game points;
- duel points;
- achievements;
- achievement progress;
- personal statistics;
- global world leaderboard;
- group/chat leaderboards;
- admin-only access to raw database tables.

Mini app requirements:

- beautiful poker-themed UI;
- personal cabinet;
- achievements page;
- points and duel points display;
- ratings and leaderboards;
- fast loading;
- mobile-first design;
- secure backend integration.

Security requirements:

- tokens only in server secrets, never in GitHub;
- real `.env` files never committed;
- PostgreSQL or another reliable central database;
- input validation;
- anti-spam and rate limits;
- safe callback handling;
- role separation: creator/admin/users;
- logs without secrets;
- backups;
- HTTPS for public endpoints;
- private admin panels behind WireGuard;
- no exposure of raw user data.

Architecture target:

- backend API on server;
- bot adapters for Telegram and MAX;
- shared core game engine;
- shared database layer;
- mini app frontend;
- admin tools;
- logging and monitoring;
- deployment through the new AI server workflow.

Need to locate existing PokerBot GitHub repository.

Search note: initial search in the user's GitHub scope for `poker bot pokerbot` returned no obvious repository. Broader GitHub search for `poker` returns public unrelated repositories, so the existing PokerBot repository name may be different or private under another name.

Next steps for PokerBot:

1. Find exact repository name or ask user for GitHub link.
2. Clone it to `/opt/repos/` on the server.
3. Audit code structure.
4. Create `POKERBOT_UPGRADE_PLAN.md`.
5. Create safe `.env.example`.
6. Design DB schema.
7. Split architecture into core/game/adapters/api/frontend/admin.
8. Deploy test backend internally through WireGuard.
9. Connect Telegram test bot.
10. Research and connect MAX bot API according to current official docs.
11. Build mini app UI.
12. Add monitoring, backups and secure deploy.
