import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles


APP_NAME = "ai-control-room"
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
CONTROL_TOKEN = os.getenv("CONTROL_ROOM_TOKEN", "").strip()

PANELS = [
    {"name": "Homepage", "url": "http://10.8.0.1:3010", "kind": "dashboard"},
    {"name": "Gatus", "url": "http://10.8.0.1:3001", "kind": "monitor"},
    {"name": "Netdata", "url": "http://10.8.0.1:19999", "kind": "metrics"},
    {"name": "Dozzle", "url": "http://10.8.0.1:8082", "kind": "logs"},
    {"name": "Adminer", "url": "http://10.8.0.1:8081", "kind": "database"},
    {"name": "Portainer", "url": "https://10.8.0.1:9443", "kind": "docker"},
    {"name": "Code Server", "url": "http://10.8.0.1:8080", "kind": "code"},
]

SERVICES = [
    "ai-agent-api",
    "ai-mcp-bridge",
    "ai-control-room",
    "poker-bot",
    "poker-redis",
    "redis-server",
    "docker",
    "ai-server-backup.timer",
]

PROJECTS = [
    {"name": "Main", "repo_path": "/opt/repos/Main", "app_path": None, "repo": "Phenolemox/Main"},
    {
        "name": "poker-bot",
        "repo_path": "/opt/repos/poker-bot",
        "app_path": "/opt/apps/poker-bot",
        "repo": "Phenolemox/poker-bot",
    },
]

HEALTH_ENDPOINTS = [
    {"name": "ai-agent-api", "url": "http://10.8.0.1:8130/health"},
    {"name": "poker-bot", "url": "http://10.8.0.1:8140/health"},
    {"name": "poker-ready", "url": "http://10.8.0.1:8140/ready"},
    {"name": "poker-sessions", "url": "http://10.8.0.1:8140/ops/sessions"},
]

ALLOWED_LOGS = {
    "ai-agent-api",
    "ai-mcp-bridge",
    "ai-control-room",
    "poker-bot",
    "poker-redis",
}

ACTION_COMMANDS = {
    "backup": ["/home/admin/bin/ai-backup-now"],
    "poker-reset-sessions": ["/home/admin/bin/poker-reset-sessions"],
    "telegram-set-commands": ["/home/admin/bin/telegram-set-commands"],
    "poker-qa": ["/home/admin/bin/poker-qa"],
}


app = FastAPI(title="AI Control Room", version="0.1.0")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "same-origin"
    response.headers["X-Frame-Options"] = "DENY"
    return response


def run(args: list[str], timeout: int = 15) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            args,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "ok": False,
            "timeout": True,
            "returncode": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
        }
    except FileNotFoundError as exc:
        return {"ok": False, "timeout": False, "returncode": 127, "stdout": "", "stderr": str(exc)}

    return {
        "ok": proc.returncode == 0,
        "timeout": False,
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }


def read_url(url: str, timeout: int = 5) -> dict[str, Any]:
    started = time.time()
    try:
        with urlopen(url, timeout=timeout) as response:
            body = response.read(200_000).decode("utf-8", "replace")
            status = response.status
    except URLError as exc:
        return {"ok": False, "url": url, "error": str(exc), "latency_ms": round((time.time() - started) * 1000)}
    except Exception as exc:
        return {"ok": False, "url": url, "error": str(exc), "latency_ms": round((time.time() - started) * 1000)}

    try:
        parsed: Any = json.loads(body)
    except Exception:
        parsed = body[:1000]

    return {
        "ok": 200 <= status < 300,
        "url": url,
        "status": status,
        "body": parsed,
        "latency_ms": round((time.time() - started) * 1000),
    }


def service_state(name: str) -> dict[str, Any]:
    is_active = run(["systemctl", "is-active", name], timeout=5)
    is_enabled = run(["systemctl", "is-enabled", name], timeout=5)
    return {
        "name": name,
        "active": is_active["stdout"],
        "enabled": is_enabled["stdout"],
        "ok": is_active["stdout"] == "active",
    }


def git_state(path: str | None) -> dict[str, Any] | None:
    if not path:
        return None
    p = Path(path)
    if not (p / ".git").exists():
        return {"path": path, "ok": False, "error": "not a git repository"}
    head = run(["git", "-C", path, "rev-parse", "--short", "HEAD"], timeout=8)
    origin = run(["git", "-C", path, "rev-parse", "--short", "origin/main"], timeout=8)
    status = run(["git", "-C", path, "status", "--short"], timeout=8)
    return {
        "path": path,
        "ok": head["ok"],
        "head": head["stdout"],
        "origin_main": origin["stdout"],
        "dirty": bool(status["stdout"]),
        "status": status["stdout"].splitlines()[:20],
    }


def filesystem_state() -> dict[str, Any]:
    disk = run(["df", "-h", "/"], timeout=5)["stdout"].splitlines()
    mem = run(["free", "-h"], timeout=5)["stdout"].splitlines()
    uptime = run(["uptime"], timeout=5)["stdout"]
    return {"disk": disk, "memory": mem, "uptime": uptime}


def latest_backups(limit: int = 8) -> list[dict[str, Any]]:
    root = Path("/opt/backups")
    if not root.exists():
        return []
    files = [p for p in root.rglob("*") if p.is_file()]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    result = []
    for path in files[:limit]:
        stat = path.stat()
        result.append(
            {
                "path": str(path),
                "size": stat.st_size,
                "mtime": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(stat.st_mtime)),
            }
        )
    return result


def app_dirs() -> list[str]:
    root = Path("/opt/apps")
    if not root.exists():
        return []
    return sorted(p.name for p in root.iterdir() if p.is_dir())


def port_snapshot() -> list[str]:
    output = run(["ss", "-ltnp"], timeout=8)["stdout"].splitlines()
    return [line for line in output if "10.8.0.1" in line][:80]


def require_action_token(x_control_room_token: str | None) -> None:
    if not CONTROL_TOKEN:
        raise HTTPException(status_code=403, detail="CONTROL_ROOM_TOKEN is not configured")
    if x_control_room_token != CONTROL_TOKEN:
        raise HTTPException(status_code=401, detail="invalid control token")


@app.get("/", include_in_schema=False)
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health")
def health():
    return {"status": "healthy", "service": APP_NAME, "write_actions_configured": bool(CONTROL_TOKEN)}


@app.get("/api/summary")
def summary():
    healths = [{**item, "result": read_url(item["url"])} for item in HEALTH_ENDPOINTS]
    projects = []
    for project in PROJECTS:
        projects.append(
            {
                **project,
                "repo_state": git_state(project["repo_path"]),
                "app_state": git_state(project["app_path"]),
            }
        )
    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "server": filesystem_state(),
        "services": [service_state(name) for name in SERVICES],
        "projects": projects,
        "health": healths,
        "panels": PANELS,
        "apps": app_dirs(),
        "ports": port_snapshot(),
        "backups": latest_backups(),
        "write_actions_configured": bool(CONTROL_TOKEN),
    }


@app.get("/api/logs/{service}")
def logs(service: str, lines: int = 120):
    clean = service.removesuffix(".service")
    if clean not in ALLOWED_LOGS:
        raise HTTPException(status_code=404, detail="unknown service")
    lines = max(1, min(lines, 400))
    result = run(["journalctl", "-u", f"{clean}.service", "-n", str(lines), "--no-pager"], timeout=15)
    return result


@app.post("/api/actions/{action}")
def action(action: str, x_control_room_token: str | None = Header(default=None)):
    require_action_token(x_control_room_token)
    if action not in ACTION_COMMANDS:
        raise HTTPException(status_code=404, detail="unknown action")
    timeout = 300 if action in {"backup", "poker-qa"} else 60
    result = run(ACTION_COMMANDS[action], timeout=timeout)
    status = 200 if result["ok"] else 500
    return JSONResponse(result, status_code=status)


@app.get("/robots.txt", include_in_schema=False)
def robots():
    return PlainTextResponse("User-agent: *\nDisallow: /\n")
