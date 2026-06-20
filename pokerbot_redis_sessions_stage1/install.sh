#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot

git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

cat > app/bot/session_state.py <<'PY'
from __future__ import annotations

import json
import os
import time
from dataclasses import asdict, dataclass, field
from secrets import token_urlsafe
from typing import Any

import redis

from app.game.cards import deal_classic, deal_holdem_duel

CLASSIC_TTL_SECONDS = 300
DUEL_TTL_SECONDS = 300
MAX_SELECTED_CARDS = 2
REDIS_PREFIX = "poker:session"


@dataclass
class ClassicSession:
    session_id: str
    chat_id: str
    chat_db_id: int
    user_id: int
    chat_type: str
    hand: list[str]
    deck: list[str]
    selected: set[int] = field(default_factory=set)
    expires_at: float = 0.0


@dataclass
class PendingDuel:
    duel_id: str
    chat_id: str
    chat_db_id: int
    challenger_user_id: int
    opponent_user_id: int
    challenger_name: str
    opponent_name: str
    expires_at: float


@dataclass
class DuelSession:
    duel_id: str
    chat_id: str
    chat_db_id: int
    challenger_user_id: int
    opponent_user_id: int
    challenger_name: str
    opponent_name: str
    table: list[str]
    hand_a: list[str]
    hand_b: list[str]
    deck: list[str]
    selected: dict[int, set[int]] = field(default_factory=dict)
    ready: dict[int, bool] = field(default_factory=dict)
    expires_at: float = 0.0


def _ttl(expires_at: float) -> int:
    return max(1, int(expires_at - time.time()))


def _classic_to_json(s: ClassicSession) -> str:
    data = asdict(s)
    data["selected"] = sorted(s.selected)
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def _classic_from_json(raw: str) -> ClassicSession:
    data = json.loads(raw)
    data["selected"] = set(int(x) for x in data.get("selected", []))
    data["chat_db_id"] = int(data["chat_db_id"])
    data["user_id"] = int(data["user_id"])
    data["expires_at"] = float(data["expires_at"])
    return ClassicSession(**data)


def _pending_to_json(d: PendingDuel) -> str:
    return json.dumps(asdict(d), ensure_ascii=False, separators=(",", ":"))


def _pending_from_json(raw: str) -> PendingDuel:
    data = json.loads(raw)
    data["chat_db_id"] = int(data["chat_db_id"])
    data["challenger_user_id"] = int(data["challenger_user_id"])
    data["opponent_user_id"] = int(data["opponent_user_id"])
    data["expires_at"] = float(data["expires_at"])
    return PendingDuel(**data)


def _duel_to_json(d: DuelSession) -> str:
    data = asdict(d)
    data["selected"] = {str(k): sorted(v) for k, v in d.selected.items()}
    data["ready"] = {str(k): bool(v) for k, v in d.ready.items()}
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def _duel_from_json(raw: str) -> DuelSession:
    data = json.loads(raw)
    data["chat_db_id"] = int(data["chat_db_id"])
    data["challenger_user_id"] = int(data["challenger_user_id"])
    data["opponent_user_id"] = int(data["opponent_user_id"])
    data["selected"] = {int(k): set(int(x) for x in v) for k, v in data.get("selected", {}).items()}
    data["ready"] = {int(k): bool(v) for k, v in data.get("ready", {}).items()}
    data["expires_at"] = float(data["expires_at"])
    return DuelSession(**data)


class SessionStore:
    def __init__(self, redis_url: str | None = None) -> None:
        self.classic: dict[str, ClassicSession] = {}
        self.pending_duels: dict[str, PendingDuel] = {}
        self.active_duels: dict[str, DuelSession] = {}
        self.redis_url = os.getenv("REDIS_URL", "") if redis_url is None else redis_url
        self._redis: redis.Redis | None | bool = None

    def _client(self) -> redis.Redis | None:
        if not self.redis_url:
            return None
        if self._redis is False:
            return None
        if self._redis is None:
            try:
                client = redis.Redis.from_url(
                    self.redis_url,
                    decode_responses=True,
                    socket_connect_timeout=1,
                    socket_timeout=1,
                    health_check_interval=30,
                )
                client.ping()
                self._redis = client
            except Exception:
                self._redis = False
                return None
        return self._redis if isinstance(self._redis, redis.Redis) else None

    def _key(self, kind: str, ident: str) -> str:
        return f"{REDIS_PREFIX}:{kind}:{ident}"

    def _get(self, kind: str, ident: str) -> str | None:
        client = self._client()
        if client is None:
            return None
        return client.get(self._key(kind, ident))

    def _set(self, kind: str, ident: str, raw: str, ttl: int) -> None:
        client = self._client()
        if client is not None:
            client.setex(self._key(kind, ident), ttl, raw)

    def _delete(self, kind: str, ident: str) -> None:
        client = self._client()
        if client is not None:
            client.delete(self._key(kind, ident))

    def _scan(self, kind: str) -> list[str]:
        client = self._client()
        if client is None:
            return []
        values: list[str] = []
        for key in client.scan_iter(match=self._key(kind, "*"), count=100):
            raw = client.get(key)
            if raw:
                values.append(raw)
        return values

    def cleanup(self) -> None:
        now = time.time()
        self.classic = {k: v for k, v in self.classic.items() if v.expires_at > now}
        self.pending_duels = {k: v for k, v in self.pending_duels.items() if v.expires_at > now}
        self.active_duels = {k: v for k, v in self.active_duels.items() if v.expires_at > now}

    def save_classic(self, s: ClassicSession) -> None:
        self.classic[s.session_id] = s
        self._set("classic", s.session_id, _classic_to_json(s), _ttl(s.expires_at))

    def save_pending_duel(self, d: PendingDuel) -> None:
        self.pending_duels[d.duel_id] = d
        self._set("pending", d.duel_id, _pending_to_json(d), _ttl(d.expires_at))

    def save_duel(self, d: DuelSession) -> None:
        self.active_duels[d.duel_id] = d
        self._set("duel", d.duel_id, _duel_to_json(d), _ttl(d.expires_at))

    def create_classic(self, *, chat_id: str, chat_db_id: int, user_id: int, chat_type: str) -> ClassicSession:
        self.cleanup()
        sid = token_urlsafe(8)
        hand, deck = deal_classic()
        s = ClassicSession(sid, chat_id, chat_db_id, user_id, chat_type, hand, deck, expires_at=time.time() + CLASSIC_TTL_SECONDS)
        self.save_classic(s)
        return s

    def get_classic(self, sid: str) -> ClassicSession | None:
        self.cleanup()
        raw = self._get("classic", sid)
        if raw:
            s = _classic_from_json(raw)
            self.classic[sid] = s
            return s
        return self.classic.get(sid)

    def pop_classic(self, sid: str) -> ClassicSession | None:
        self.cleanup()
        raw = self._get("classic", sid)
        self._delete("classic", sid)
        if raw:
            self.classic.pop(sid, None)
            return _classic_from_json(raw)
        return self.classic.pop(sid, None)

    def _pending_values(self) -> list[PendingDuel]:
        values = list(self.pending_duels.values())
        for raw in self._scan("pending"):
            try:
                d = _pending_from_json(raw)
            except Exception:
                continue
            if all(existing.duel_id != d.duel_id for existing in values):
                values.append(d)
        return values

    def _duel_values(self) -> list[DuelSession]:
        values = list(self.active_duels.values())
        for raw in self._scan("duel"):
            try:
                d = _duel_from_json(raw)
            except Exception:
                continue
            if all(existing.duel_id != d.duel_id for existing in values):
                values.append(d)
        return values

    def create_pending_duel(
        self,
        *,
        chat_id: str,
        chat_db_id: int,
        challenger_user_id: int,
        opponent_user_id: int,
        challenger_name: str,
        opponent_name: str,
    ) -> tuple[PendingDuel | None, str | None]:
        self.cleanup()
        players = {challenger_user_id, opponent_user_id}
        for d in self._pending_values():
            if d.chat_id == chat_id and players & {d.challenger_user_id, d.opponent_user_id}:
                return None, "У одного из игроков уже висит вызов."
        for d in self._duel_values():
            if d.chat_id == chat_id and players & {d.challenger_user_id, d.opponent_user_id}:
                return None, "У одного из игроков уже идёт дуэль."
        did = token_urlsafe(8)
        d = PendingDuel(did, chat_id, chat_db_id, challenger_user_id, opponent_user_id, challenger_name, opponent_name, time.time() + DUEL_TTL_SECONDS)
        self.save_pending_duel(d)
        return d, None

    def get_pending_duel(self, did: str) -> PendingDuel | None:
        self.cleanup()
        raw = self._get("pending", did)
        if raw:
            d = _pending_from_json(raw)
            self.pending_duels[did] = d
            return d
        return self.pending_duels.get(did)

    def pop_pending_duel(self, did: str) -> PendingDuel | None:
        self.cleanup()
        raw = self._get("pending", did)
        self._delete("pending", did)
        if raw:
            self.pending_duels.pop(did, None)
            return _pending_from_json(raw)
        return self.pending_duels.pop(did, None)

    def start_duel(self, pending: PendingDuel) -> DuelSession:
        table, hand_a, hand_b, deck = deal_holdem_duel()
        d = DuelSession(
            duel_id=pending.duel_id,
            chat_id=pending.chat_id,
            chat_db_id=pending.chat_db_id,
            challenger_user_id=pending.challenger_user_id,
            opponent_user_id=pending.opponent_user_id,
            challenger_name=pending.challenger_name,
            opponent_name=pending.opponent_name,
            table=table,
            hand_a=hand_a,
            hand_b=hand_b,
            deck=deck,
            selected={pending.challenger_user_id: set(), pending.opponent_user_id: set()},
            ready={pending.challenger_user_id: False, pending.opponent_user_id: False},
            expires_at=time.time() + DUEL_TTL_SECONDS,
        )
        self.save_duel(d)
        return d

    def get_duel(self, did: str) -> DuelSession | None:
        self.cleanup()
        raw = self._get("duel", did)
        if raw:
            d = _duel_from_json(raw)
            self.active_duels[did] = d
            return d
        return self.active_duels.get(did)

    def pop_duel(self, did: str) -> DuelSession | None:
        self.cleanup()
        raw = self._get("duel", did)
        self._delete("duel", did)
        if raw:
            self.active_duels.pop(did, None)
            return _duel_from_json(raw)
        return self.active_duels.pop(did, None)

    def stats(self) -> dict[str, Any]:
        client = self._client()
        redis_counts = {"classic": 0, "pending": 0, "duel": 0}
        redis_ok = False
        if client is not None:
            redis_ok = True
            for kind in redis_counts:
                redis_counts[kind] = sum(1 for _ in client.scan_iter(match=self._key(kind, "*"), count=100))
        return {
            "redis_ok": redis_ok,
            "memory": {"classic": len(self.classic), "pending": len(self.pending_duels), "duel": len(self.active_duels)},
            "redis": redis_counts,
        }


def toggle_selected(selected: set[int], index: int) -> tuple[bool, str | None]:
    if index in selected:
        selected.remove(index)
        return True, None
    if len(selected) >= MAX_SELECTED_CARDS:
        return False, "Можно выбрать максимум 2 карты. Сними одну и выбери другую."
    selected.add(index)
    return True, None


def apply_exchange(hand: list[str], deck: list[str], selected: set[int]) -> tuple[list[str], list[str], list[str]]:
    new_hand = list(hand)
    new_deck = list(deck)
    removed: list[str] = []
    for index in sorted(selected):
        if 0 <= index < len(new_hand) and new_deck:
            removed.append(new_hand[index])
            new_hand[index] = new_deck.pop(0)
    return new_hand, new_deck, removed


sessions = SessionStore()
PY

python3 - <<'PY'
from pathlib import Path
import re
p = Path('app/bot/telegram.py')
s = p.read_text(encoding='utf-8')

# Persist classic selection after each card toggle.
s = re.sub(
    r'(\n\s+_ok, error = toggle_selected\(s\.selected, int\(idx_s\)\)\n)(?!\s+sessions\.save_classic\(s\))',
    r'\1        sessions.save_classic(s)\n',
    s,
    count=1,
)

# Persist duel selection after each card toggle.
s = re.sub(
    r'(\n\s+_ok, error = toggle_selected\((?:d|duel)\.selected\[user\.id\], int\(idx_s\)\)\n)(?!\s+sessions\.save_duel\()',
    r'\1        sessions.save_duel(d)\n',
    s,
    count=1,
)

# Persist duel readiness/exchange before resolving or waiting for second player.
if 'sessions.save_duel(d)\n        if all(d.ready.values()):' not in s:
    s = s.replace('        if all(d.ready.values()):\n', '        sessions.save_duel(d)\n        if all(d.ready.values()):\n', 1)

# Add session stats to ops module if it imports sessions elsewhere later.
p.write_text(s, encoding='utf-8')
print('telegram persistence hooks patched')
PY

python3 - <<'PY'
from pathlib import Path
p = Path('app/api/ops.py')
s = p.read_text(encoding='utf-8')
if 'from app.bot.session_state import sessions' not in s:
    s = s.replace('from app.core.redis_client import redis_health\n', 'from app.core.redis_client import redis_health\nfrom app.bot.session_state import sessions\n')
if '@router.get("/sessions")' not in s:
    s += '\n\n@router.get("/sessions")\nasync def ops_sessions():\n    return {"ok": True, "sessions": sessions.stats()}\n'
p.write_text(s, encoding='utf-8')
PY

cat > tests/test_session_state_redis_stage.py <<'PY'
from app.bot.session_state import SessionStore, toggle_selected


def test_memory_store_classic_selection_persists():
    store = SessionStore(redis_url='')
    s = store.create_classic(chat_id='1', chat_db_id=1, user_id=10, chat_type='private')
    ok, err = toggle_selected(s.selected, 0)
    assert ok and err is None
    store.save_classic(s)
    loaded = store.get_classic(s.session_id)
    assert loaded is not None
    assert loaded.selected == {0}


def test_memory_store_duel_conflict():
    store = SessionStore(redis_url='')
    d, err = store.create_pending_duel(chat_id='c', chat_db_id=1, challenger_user_id=1, opponent_user_id=2, challenger_name='A', opponent_name='B')
    assert d is not None and err is None
    d2, err2 = store.create_pending_duel(chat_id='c', chat_db_id=1, challenger_user_id=1, opponent_user_id=3, challenger_name='A', opponent_name='C')
    assert d2 is None
    assert err2


def test_stats_shape():
    store = SessionStore(redis_url='')
    stats = store.stats()
    assert stats['memory']['classic'] == 0
    assert stats['redis_ok'] is False
PY

./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git add .
git commit -m 'Add Redis-backed session store stage 1' || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/redis && echo
curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions && echo

echo POKER_REDIS_SESSIONS_STAGE1_DONE
