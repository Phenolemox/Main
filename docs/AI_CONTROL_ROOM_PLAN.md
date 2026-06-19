# AI Control Room Plan

## Main goal

Build a private AI server control room where the user writes normal text tasks and the system helps turn them into working server projects.

Target workflow:

1. User describes a task in plain language.
2. AI plans the project structure.
3. AI creates files and folders in `/opt/apps` or `/opt/repos`.
4. AI connects GitHub when needed.
5. AI runs or prepares deployment through systemd or Docker.
6. AI checks logs and health endpoints.
7. AI reports the result in a simple status format.

## Current server baseline

Server: ai-server-amsterdam-01
Public IP: 5.129.229.170
VPN server IP: 10.8.0.1
Main user: admin
OS: Ubuntu 24.04

Existing internal services:

- Dashboard: http://10.8.0.1:3010
- Portainer: https://10.8.0.1:9443
- Dozzle: http://10.8.0.1:8082
- Gatus: http://10.8.0.1:3001
- Netdata: http://10.8.0.1:19999
- Code Server: http://10.8.0.1:8080
- Adminer: http://10.8.0.1:8081
- Lab Hello Site: http://10.8.0.1:8010

Existing infrastructure:

- WireGuard VPN
- GitHub CLI authorized as Phenolemox
- PostgreSQL
- MariaDB
- Redis
- Daily backups
- Health status command: `ai-status`

## AI tools roles

### ChatGPT Pro

Main architect, planner, code generation, GitHub coordination, server task planning.

### Claude / Claude Code

Code review, complex implementation, refactoring, larger codebase reasoning.

### Perplexity

Current documentation search, library checks, service comparisons, issue research.

### Midjourney / Kling / Seedance / Syntx / Napkin / NotebookLM

Creative and research tools, not core server execution tools.

## Rules

Never commit:

- real `.env` files
- passwords
- API tokens
- private SSH keys
- WireGuard configs with private keys
- production database dumps

Allowed in GitHub:

- source code
- README files
- `.env.example`
- safe templates
- deployment scripts without secrets
- architecture docs

## Planned local folder

Create:

`/opt/apps/ai-control-room`

Initial contents:

- `README.md`
- `AGENT_RULES.md`
- `TOOLS.md`
- `WORKFLOW.md`
- `PROJECT_TEMPLATE.md`
- `COMMANDS.md`
- `SECURITY.md`

## First operating mode

Manual-confirmation mode:

- AI gives commands.
- User executes them.
- AI checks output.
- Nothing destructive is done automatically.

Later operating mode:

- Add server-side helper scripts.
- Add project generator commands.
- Add GitHub issue/task templates.
- Add optional local or web agent interface.

## Region and account constraint

The user may periodically be in Russia. Some services or accounts may not work from Russian locations. Access must be designed around the user's working accounts and the private Amsterdam server/VPN setup.
