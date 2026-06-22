# AI Control Room App

FastAPI web UI for the AI server control room.

Runtime target:

- `/opt/apps/ai-control-room`
- `ai-control-room.service`
- `http://10.8.0.1:8150`

Write actions require `CONTROL_ROOM_TOKEN` in `/opt/apps/ai-control-room/.env`.

Read-only status pages intentionally avoid printing secrets.
