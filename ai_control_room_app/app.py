import hmac
import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from fastapi import FastAPI, Header, HTTPException, Request as FastAPIRequest, Response
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles


APP_NAME = "ai-control-room"
APP_VERSION = "0.3.0"
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
CONTROL_TOKEN = os.getenv("CONTROL_ROOM_TOKEN", "").strip()
SESSION_COOKIE = "ai_control_room_session"
SESSION_TTL_SECONDS = int(os.getenv("CONTROL_ROOM_SESSION_TTL_SECONDS", "43200"))
COOKIE_SECURE = os.getenv("CONTROL_ROOM_COOKIE_SECURE", "").strip().lower() in {"1", "true", "yes"}
POKER_ADMIN_BASE_URL = os.getenv("POKER_ADMIN_BASE_URL", "http://10.8.0.1:8140").rstrip("/")
POKER_ADMIN_TOKEN = os.getenv("POKER_ADMIN_TOKEN", "").strip()
PUBLIC_DOMAIN = os.getenv("PUBLIC_DOMAIN", "ai-alliance.pro").strip()
LOCAL_MIRROR_PATH = os.getenv("LOCAL_MIRROR_PATH", r"C:\\Нейросети\\Боты\\, local_bots_mirror/")

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
    "bots-hub",
    "poker-bot",
    "cb-balloons-bot",
    "autobot-bot",
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
    {
        "name": "cb-balloons-bot",
        "repo_path": "/opt/repos/Main",
        "app_path": "/opt/apps/cb-balloons-bot",
        "repo": "Phenolemox/Main",
    },
    {
        "name": "autobot-bot",
        "repo_path": "/opt/repos/Main",
        "app_path": "/opt/apps/autobot-bot",
        "repo": "Phenolemox/Main",
    },
    {
        "name": "bots-hub",
        "repo_path": "/opt/repos/Main",
        "app_path": "/opt/apps/bots-hub",
        "repo": "Phenolemox/Main",
    },
]

HEALTH_ENDPOINTS = [
    {"name": "ai-agent-api", "url": "http://10.8.0.1:8130/health"},
    {"name": "poker-bot", "url": "http://10.8.0.1:8140/health"},
    {"name": "poker-ready", "url": "http://10.8.0.1:8140/ready"},
    {"name": "poker-sessions", "url": "http://10.8.0.1:8140/ops/sessions"},
    {"name": "cb-balloons-bot", "url": "http://10.8.0.1:8160/health"},
    {"name": "cb-balloons-ready", "url": "http://10.8.0.1:8160/ready"},
    {"name": "autobot-bot", "url": "http://10.8.0.1:8161/health"},
    {"name": "autobot-ready", "url": "http://10.8.0.1:8161/ready"},
    {"name": "bots-hub", "url": "http://10.8.0.1:8170/health"},
    {"name": "control-room", "url": "http://10.8.0.1:8150/health"},
]

BOTS = [
    {
        "id": "poker-bot",
        "name": "MyPoker",
        "emoji": "🃏",
        "service": "poker-bot",
        "repo": "Phenolemox/poker-bot",
        "api": "http://10.8.0.1:8140",
        "miniapp": "http://10.8.0.1:8140/miniapp",
        "public": f"https://poker.{PUBLIC_DOMAIN}",
        "public_miniapp": f"https://poker.{PUBLIC_DOMAIN}/miniapp",
        "max_webhook": f"https://poker.{PUBLIC_DOMAIN}/webhooks/max",
        "telegram": "https://t.me/mypokerbotofficial_bot",
        "admin_api_configured": bool(POKER_ADMIN_TOKEN),
        "admin_kind": "poker",
    },
    {
        "id": "cb-balloons-bot",
        "name": "CB Balloons",
        "emoji": "🎈",
        "service": "cb-balloons-bot",
        "repo": "Phenolemox/Main",
        "api": "http://10.8.0.1:8160",
        "miniapp": "http://10.8.0.1:8160/miniapp",
        "public": f"https://balloons.{PUBLIC_DOMAIN}",
        "public_miniapp": f"https://balloons.{PUBLIC_DOMAIN}/miniapp",
        "max_webhook": f"https://balloons.{PUBLIC_DOMAIN}/webhooks/max",
        "telegram": "https://t.me/CB_Balloonsbot",
        "admin_api_configured": bool(os.getenv("CB_BALLOONS_ADMIN_TOKEN", "").strip()),
        "admin_kind": "generic",
        "admin_path": "/admin/summary",
    },
    {
        "id": "autobot-bot",
        "name": "Autobot",
        "emoji": "🚓",
        "service": "autobot-bot",
        "repo": "Phenolemox/Main",
        "api": "http://10.8.0.1:8161",
        "miniapp": "http://10.8.0.1:8161/miniapp",
        "public": f"https://autobot.{PUBLIC_DOMAIN}",
        "public_miniapp": f"https://autobot.{PUBLIC_DOMAIN}/miniapp",
        "max_webhook": f"https://autobot.{PUBLIC_DOMAIN}/webhooks/max",
        "telegram": "https://t.me/Inspectorauto_bot",
        "admin_api_configured": bool(os.getenv("AUTOBOT_ADMIN_TOKEN", "").strip()),
        "admin_kind": "generic",
        "admin_path": "/admin/summary",
    },
]

TOGGLEABLE_SERVICES = {bot["service"] for bot in BOTS}

ALLOWED_LOGS = {
    "ai-agent-api",
    "ai-mcp-bridge",
    "ai-control-room",
    "bots-hub",
    "poker-bot",
    "cb-balloons-bot",
    "autobot-bot",
    "poker-redis",
}

ACTION_COMMANDS = {
    "backup": ["/home/admin/bin/ai-backup-now"],
    "poker-reset-sessions": ["/home/admin/bin/poker-reset-sessions"],
    "telegram-set-commands": ["/home/admin/bin/telegram-set-commands"],
    "poker-qa": ["/home/admin/bin/poker-qa"],
    "bots-platform-deploy": ["/home/admin/bin/bots-platform-deploy"],
}


app = FastAPI(title="AI Control Room", version=APP_VERSION)
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


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    timeout: int = 10,
) -> dict[str, Any]:
    data = None
    request_headers = {"Accept": "application/json"}
    if headers:
        request_headers.update(headers)
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        request_headers["Content-Type"] = "application/json"
    started = time.time()
    request = Request(url, data=data, headers=request_headers, method=method)
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read(500_000).decode("utf-8", "replace")
            status = response.status
    except HTTPError as exc:
        body = exc.read(100_000).decode("utf-8", "replace")
        try:
            parsed_error: Any = json.loads(body)
        except Exception:
            parsed_error = body[:1000]
        return {
            "ok": False,
            "status": exc.code,
            "url": url,
            "body": parsed_error,
            "latency_ms": round((time.time() - started) * 1000),
        }
    except URLError as exc:
        return {"ok": False, "url": url, "error": str(exc), "latency_ms": round((time.time() - started) * 1000)}
    except Exception as exc:
        return {"ok": False, "url": url, "error": str(exc), "latency_ms": round((time.time() - started) * 1000)}

    try:
        parsed: Any = json.loads(body)
    except Exception:
        parsed = body[:2000]
    return {
        "ok": 200 <= status < 300,
        "status": status,
        "url": url,
        "body": parsed,
        "latency_ms": round((time.time() - started) * 1000),
    }


def poker_admin_headers() -> dict[str, str]:
    if not POKER_ADMIN_TOKEN:
        raise HTTPException(status_code=503, detail="POKER_ADMIN_TOKEN is not configured")
    return {"X-Admin-Token": POKER_ADMIN_TOKEN, "X-Admin-Actor": "ai-control-room"}


def poker_admin_request(
    path: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    timeout: int = 15,
) -> dict[str, Any]:
    result = request_json(
        f"{POKER_ADMIN_BASE_URL}{path}",
        method=method,
        headers=poker_admin_headers(),
        payload=payload,
        timeout=timeout,
    )
    if not result["ok"]:
        status = result.get("status") or 502
        raise HTTPException(status_code=status, detail=result.get("body") or result.get("error") or "poker admin error")
    return result["body"]


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


def github_state() -> dict[str, Any]:
    auth = run(["gh", "auth", "status", "-h", "github.com"], timeout=8)
    repos = run(["gh", "repo", "list", "Phenolemox", "--limit", "20", "--json", "name,updatedAt,url"], timeout=12)
    items: list[Any] = []
    if repos["ok"]:
        try:
            items = json.loads(repos["stdout"] or "[]")
        except Exception:
            items = []
    return {
        "ok": auth["ok"],
        "authenticated": auth["ok"],
        "repos": items[:12],
        "raw_status": auth["stdout"][:400] if auth["ok"] else auth["stderr"][:400],
    }


def generic_bot_admin_request(bot_id: str) -> dict[str, Any]:
    token_map = {
        "cb-balloons-bot": os.getenv("CB_BALLOONS_ADMIN_TOKEN", "").strip(),
        "autobot-bot": os.getenv("AUTOBOT_ADMIN_TOKEN", "").strip(),
    }
    base_map = {
        "cb-balloons-bot": "http://10.8.0.1:8160",
        "autobot-bot": "http://10.8.0.1:8161",
    }
    token = token_map.get(bot_id, "")
    base = base_map.get(bot_id, "")
    if not token or not base:
        raise HTTPException(status_code=503, detail=f"admin token not configured for {bot_id}")
    result = request_json(
        f"{base}/admin/summary",
        headers={"X-Admin-Token": token},
        timeout=10,
    )
    if not result["ok"]:
        raise HTTPException(status_code=result.get("status") or 502, detail=result.get("body") or "bot admin error")
    return result["body"]


def port_snapshot() -> list[str]:
    output = run(["ss", "-ltnp"], timeout=8)["stdout"].splitlines()
    return [line for line in output if "10.8.0.1" in line][:80]


def _read_cpu_times() -> tuple[int, int] | None:
    try:
        with open("/proc/stat", "r", encoding="utf-8") as handle:
            line = handle.readline()
    except OSError:
        return None
    if not line.startswith("cpu "):
        return None
    parts = [int(x) for x in line.split()[1:]]
    idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
    total = sum(parts)
    return idle, total


def cpu_percent(sample_seconds: float = 0.25) -> float | None:
    first = _read_cpu_times()
    if not first:
        return None
    time.sleep(sample_seconds)
    second = _read_cpu_times()
    if not second:
        return None
    idle_delta = second[0] - first[0]
    total_delta = second[1] - first[1]
    if total_delta <= 0:
        return None
    return round((1 - idle_delta / total_delta) * 100, 1)


def memory_metrics() -> dict[str, Any]:
    info: dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as handle:
            for line in handle:
                key, _, rest = line.partition(":")
                value = rest.strip().split()
                if value and value[0].isdigit():
                    info[key] = int(value[0])  # kB
    except OSError:
        return {}
    total = info.get("MemTotal", 0)
    available = info.get("MemAvailable", info.get("MemFree", 0))
    used = max(total - available, 0)
    percent = round(used / total * 100, 1) if total else None
    return {
        "total_mb": round(total / 1024),
        "used_mb": round(used / 1024),
        "available_mb": round(available / 1024),
        "percent": percent,
    }


def disk_metrics() -> dict[str, Any]:
    try:
        usage = os.statvfs("/")
    except OSError:
        return {}
    total = usage.f_blocks * usage.f_frsize
    free = usage.f_bavail * usage.f_frsize
    used = total - (usage.f_bfree * usage.f_frsize)
    percent = round(used / total * 100, 1) if total else None
    return {
        "total_gb": round(total / 1024 ** 3, 1),
        "used_gb": round(used / 1024 ** 3, 1),
        "free_gb": round(free / 1024 ** 3, 1),
        "percent": percent,
    }


def load_metrics() -> dict[str, Any]:
    try:
        load1, load5, load15 = os.getloadavg()
    except (OSError, AttributeError):
        return {}
    cores = os.cpu_count() or 1
    return {
        "load1": round(load1, 2),
        "load5": round(load5, 2),
        "load15": round(load15, 2),
        "cores": cores,
        "load1_percent": round(min(load1 / cores * 100, 100), 1),
    }


def uptime_seconds() -> int | None:
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as handle:
            return int(float(handle.readline().split()[0]))
    except (OSError, ValueError, IndexError):
        return None


def server_metrics() -> dict[str, Any]:
    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "cpu_percent": cpu_percent(),
        "memory": memory_metrics(),
        "disk": disk_metrics(),
        "load": load_metrics(),
        "uptime_seconds": uptime_seconds(),
    }


def toggle_service(service: str, action: str) -> dict[str, Any]:
    if service not in TOGGLEABLE_SERVICES:
        raise HTTPException(status_code=404, detail="unknown or non-toggleable service")
    if action not in {"start", "stop", "restart", "enable", "disable"}:
        raise HTTPException(status_code=400, detail="invalid action")
    result = run(["systemctl", action, service], timeout=30)
    state = service_state(service)
    if not result["ok"] and not (action in {"start", "restart"} and state["ok"]):
        raise HTTPException(
            status_code=502,
            detail={
                "action": action,
                "service": service,
                "stderr": result["stderr"][:400] or result["stdout"][:400],
                "hint": "systemctl auth — ensure polkit rule 49-bots-control.rules is installed",
            },
        )
    return {"ok": True, "service": service, "action": action, "state": state}


def max_platform_status() -> dict[str, Any]:
    bots = []
    for bot in BOTS:
        env_prefix = {
            "poker-bot": "MAX",
            "cb-balloons-bot": "CB_BALLOONS_MAX",
            "autobot-bot": "AUTOBOT_MAX",
        }.get(bot["id"], "MAX")
        token = (
            os.getenv("MAX_BOT_TOKEN", "")
            if bot["id"] == "poker-bot"
            else os.getenv(f"{env_prefix}_BOT_TOKEN", "")
        ).strip()
        bots.append(
            {
                "id": bot["id"],
                "name": bot["name"],
                "emoji": bot["emoji"],
                "webhook_url": bot["max_webhook"],
                "miniapp_url": bot["public_miniapp"],
                "bot_token_configured": bool(token),
                "webhook_health": read_url(f"{bot['api']}/health"),
            }
        )
    configured = sum(1 for b in bots if b["bot_token_configured"])
    return {
        "platform": "MAX",
        "ready": configured == len(bots),
        "configured_count": configured,
        "total": len(bots),
        "bots": bots,
        "note": (
            "Mini App работает в Telegram и MAX (dual-SDK). Для активации MAX-бота "
            "добавьте MAX_BOT_TOKEN в /opt/secrets/bots-platform.env и зарегистрируйте webhook."
        ),
    }


def local_sync_status() -> dict[str, Any]:
    return {
        "mirror_paths": [p.strip() for p in LOCAL_MIRROR_PATH.split(",") if p.strip()],
        "workspace": "C:/Users/xafiz/OneDrive/Documents/Сервер проект",
        "repos": ["Phenolemox/Main", "Phenolemox/poker-bot"],
        "server_repo_main": git_state("/opt/repos/Main"),
        "server_repo_poker": git_state("/opt/repos/poker-bot"),
        "note": (
            "Локальное зеркало синхронизируется через GitHub (Main и poker-bot). "
            "Локальный ПК не имеет публичного endpoint — статус отражает серверные репозитории."
        ),
    }


def make_session_cookie(now: int | None = None) -> str:
    if not CONTROL_TOKEN:
        raise HTTPException(status_code=403, detail="CONTROL_ROOM_TOKEN is not configured")
    issued_at = int(now or time.time())
    expires_at = issued_at + SESSION_TTL_SECONDS
    payload = f"v1:{expires_at}"
    signature = hmac.new(CONTROL_TOKEN.encode("utf-8"), payload.encode("utf-8"), "sha256").hexdigest()
    return f"v1.{expires_at}.{signature}"


def session_cookie_valid(value: str | None, now: int | None = None) -> bool:
    if not CONTROL_TOKEN or not value:
        return False
    parts = value.split(".")
    if len(parts) != 3 or parts[0] != "v1":
        return False
    try:
        expires_at = int(parts[1])
    except ValueError:
        return False
    if expires_at < int(now or time.time()):
        return False
    payload = f"v1:{expires_at}"
    expected = hmac.new(CONTROL_TOKEN.encode("utf-8"), payload.encode("utf-8"), "sha256").hexdigest()
    return hmac.compare_digest(parts[2], expected)


def request_authenticated(request: FastAPIRequest, x_control_room_token: str | None) -> bool:
    if CONTROL_TOKEN and x_control_room_token and hmac.compare_digest(x_control_room_token, CONTROL_TOKEN):
        return True
    return session_cookie_valid(request.cookies.get(SESSION_COOKIE))


def require_action_auth(request: FastAPIRequest, x_control_room_token: str | None) -> None:
    if not CONTROL_TOKEN:
        raise HTTPException(status_code=403, detail="CONTROL_ROOM_TOKEN is not configured")
    if not request_authenticated(request, x_control_room_token):
        raise HTTPException(status_code=401, detail="login required")


@app.get("/", include_in_schema=False)
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": APP_NAME,
        "write_actions_configured": bool(CONTROL_TOKEN),
        "poker_admin_configured": bool(POKER_ADMIN_TOKEN),
    }


@app.get("/api/auth/me")
def auth_me(request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    return {
        "configured": bool(CONTROL_TOKEN),
        "authenticated": request_authenticated(request, x_control_room_token),
        "session_ttl_seconds": SESSION_TTL_SECONDS,
    }


@app.post("/api/auth/login")
def auth_login(payload: dict[str, Any], response: Response):
    if not CONTROL_TOKEN:
        raise HTTPException(status_code=403, detail="CONTROL_ROOM_TOKEN is not configured")
    password = str(payload.get("password") or payload.get("token") or "")
    if not hmac.compare_digest(password, CONTROL_TOKEN):
        raise HTTPException(status_code=401, detail="invalid login")
    response.set_cookie(
        SESSION_COOKIE,
        make_session_cookie(),
        max_age=SESSION_TTL_SECONDS,
        httponly=True,
        secure=COOKIE_SECURE,
        samesite="strict",
        path="/",
    )
    return {
        "ok": True,
        "authenticated": True,
        "ttl_seconds": SESSION_TTL_SECONDS,
        "session_ttl_seconds": SESSION_TTL_SECONDS,
    }


@app.post("/api/auth/logout")
def auth_logout(response: Response):
    response.delete_cookie(SESSION_COOKIE, path="/")
    return {"ok": True}


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
        "metrics": server_metrics(),
        "services": [service_state(name) for name in SERVICES],
        "projects": projects,
        "health": healths,
        "panels": PANELS,
        "bots": BOTS,
        "apps": app_dirs(),
        "ports": port_snapshot(),
        "backups": latest_backups(),
        "write_actions_configured": bool(CONTROL_TOKEN),
        "poker_admin_configured": bool(POKER_ADMIN_TOKEN),
        "github": github_state(),
        "max": max_platform_status(),
        "local": local_sync_status(),
        "public_domain": PUBLIC_DOMAIN,
        "hub_url": f"https://bots.{PUBLIC_DOMAIN}",
        "version": APP_VERSION,
    }


@app.get("/api/bots")
def bots():
    return {
        "items": [
            {
                **bot,
                "service_state": service_state(bot["service"]),
                "health": read_url(f"{bot['api']}/health"),
            }
            for bot in BOTS
        ]
    }


@app.get("/api/github")
def github():
    return github_state()


@app.get("/api/server/metrics")
def api_server_metrics():
    return server_metrics()


@app.get("/api/max/status")
def api_max_status():
    return max_platform_status()


@app.get("/api/local/sync-status")
def api_local_sync():
    return local_sync_status()


@app.post("/api/bots/{bot_id}/toggle")
def api_bot_toggle(
    bot_id: str,
    payload: dict[str, Any],
    request: FastAPIRequest,
    x_control_room_token: str | None = Header(default=None),
):
    require_action_auth(request, x_control_room_token)
    bot = next((b for b in BOTS if b["id"] == bot_id), None)
    if not bot:
        raise HTTPException(status_code=404, detail="unknown bot")
    action = str(payload.get("action") or "").strip().lower()
    return toggle_service(bot["service"], action)


@app.get("/api/bots/{bot_id}/admin")
def bot_admin(bot_id: str, request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    if bot_id == "poker-bot":
        raise HTTPException(status_code=400, detail="use /api/poker-admin for poker-bot")
    return generic_bot_admin_request(bot_id)


@app.get("/api/poker-admin")
def poker_admin(request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return {
        "summary": poker_admin_request("/admin/summary"),
        "users": poker_admin_request("/admin/users"),
        "chats": poker_admin_request("/admin/chats"),
        "settings": poker_admin_request("/admin/settings"),
        "leaderboards": poker_admin_request("/admin/leaderboards"),
        "attempts": poker_admin_request("/admin/attempts"),
        "audit": poker_admin_request("/admin/audit?limit=30"),
        "sessions": read_url(f"{POKER_ADMIN_BASE_URL}/ops/sessions"),
    }


@app.post("/api/poker-admin/score-adjust")
def poker_score_adjust(payload: dict[str, Any], request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return poker_admin_request("/admin/score/adjust", method="POST", payload=payload)


@app.post("/api/poker-admin/score-reset")
def poker_score_reset(payload: dict[str, Any], request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return poker_admin_request("/admin/score/reset", method="POST", payload=payload)


@app.post("/api/poker-admin/attempts-grant")
def poker_attempts_grant(payload: dict[str, Any], request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return poker_admin_request("/admin/attempts/grant", method="POST", payload=payload)


@app.post("/api/poker-admin/attempts-reset")
def poker_attempts_reset(payload: dict[str, Any], request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return poker_admin_request("/admin/attempts/reset", method="POST", payload=payload)


@app.patch("/api/poker-admin/users/{user_id}/block")
def poker_user_block(user_id: int, payload: dict[str, Any], request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return poker_admin_request(f"/admin/users/{user_id}/block", method="PATCH", payload=payload)


@app.put("/api/poker-admin/settings/{key}")
def poker_setting_update(key: str, payload: dict[str, Any], request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    return poker_admin_request(f"/admin/settings/{key}", method="PUT", payload=payload)


@app.get("/api/logs/{service}")
def logs(service: str, lines: int = 120):
    clean = service.removesuffix(".service")
    if clean not in ALLOWED_LOGS:
        raise HTTPException(status_code=404, detail="unknown service")
    lines = max(1, min(lines, 400))
    result = run(["journalctl", "-u", f"{clean}.service", "-n", str(lines), "--no-pager"], timeout=15)
    return result


@app.post("/api/actions/{action}")
def action(action: str, request: FastAPIRequest, x_control_room_token: str | None = Header(default=None)):
    require_action_auth(request, x_control_room_token)
    if action not in ACTION_COMMANDS:
        raise HTTPException(status_code=404, detail="unknown action")
    timeout = 300 if action in {"backup", "poker-qa", "bots-platform-deploy"} else 60
    result = run(ACTION_COMMANDS[action], timeout=timeout)
    status = 200 if result["ok"] else 500
    return JSONResponse(result, status_code=status)


@app.get("/robots.txt", include_in_schema=False)
def robots():
    return PlainTextResponse("User-agent: *\nDisallow: /\n")
