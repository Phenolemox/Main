#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="Phenolemox/poker-bot"
TARGET_DIR="/opt/repos/poker-bot"

if [ ! -d "$TARGET_DIR/.git" ]; then
  rm -rf "$TARGET_DIR"
  gh repo clone "$TARGET_REPO" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
git remote set-url origin "https://github.com/${TARGET_REPO}.git" 2>/dev/null || true
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true

python3 - <<'PY'
from pathlib import Path
from textwrap import dedent
import shutil

root = Path('/opt/repos/poker-bot')

for name in ['app', 'docs', 'tests']:
    p = root / name
    if p.exists():
        shutil.rmtree(p)
for name in ['README.md', 'requirements.txt', 'amvera.yml']:
    p = root / name
    if p.exists():
        p.unlink()

files = {
'.gitignore': r'''
.env
.venv/
__pycache__/
*.pyc
*.db
*.sqlite
.pytest_cache/
.coverage
.DS_Store
node_modules/
dist/
build/
'''.strip() + '\n',

'README.md': r'''
# poker-bot

Модульный poker-bot backend для Telegram, MAX, Mini App и внутренней админки.

## Stage 2

Готово:

- FastAPI backend.
- Health / readiness.
- Game engine: 5-card classic, holdem-duel evaluation.
- SQLite stage DB layer через SQLAlchemy async.
- Таблицы: users, platform_identities, chats, chat_memberships, score_ledger, achievements, user_achievements, settings, admin_audit_log.
- Leaderboards API.
- Admin API foundation.
- Mini App placeholder.

Следующее:

- Telegram adapter.
- MAX adapter.
- Webhook signature enforcement.
- Bot commands parity со старым ботом.
- Admin UI.
- Mini App rooms / holdem 9-max.

## Security

- Реальные `.env` не коммитятся.
- Токены только в `/opt/apps/poker-bot/.env`.
- Admin API требует `X-Admin-Token`, если задан `ADMIN_TOKEN`.
- Stage database сейчас SQLite, production migration позже на PostgreSQL.
'''.strip() + '\n',

'requirements.txt': r'''
fastapi==0.115.6
uvicorn[standard]==0.32.1
httpx==0.28.1
pydantic-settings==2.6.1
python-dotenv==1.0.1
sqlalchemy[asyncio]==2.0.36
asyncpg==0.30.0
aiosqlite==0.20.0
redis==5.2.1
pytest==8.3.4
'''.strip() + '\n',

'amvera.yml': r'''
---
version: null
meta:
  environment: python
  toolchain:
    name: pip
    version: "3.12"
build:
  requirementsPath: requirements.txt
run:
  scriptName: "python -m uvicorn app.main:app --host 0.0.0.0 --port 80"
  persistenceMount: /data
  containerPort: 80
'''.strip() + '\n',

'docs/ARCHITECTURE.md': r'''
# Poker Bot Architecture

```text
Telegram / MAX
    ↓ HTTPS webhook
public reverse proxy :443
    ↓ internal
poker-bot FastAPI :8140
    ↓
PostgreSQL + Redis later
SQLite stage now
```

## Modes

```text
private chat:
  /start, /cards, /topscore, /help, profile/miniapp

group chat:
  /start, /cards, /duel, /topscore, /topduel, /reset by admin

miniapp:
  profile, achievements, global rating, group ratings, rooms, holdem 9-max

admin:
  users, chats, scores, bans, achievements, settings, audit
```
'''.strip() + '\n',

'app/__init__.py': '',
'app/core/__init__.py': '',
'app/db/__init__.py': '',
'app/game/__init__.py': '# game package\n',
'app/api/__init__.py': '# api package\n',

'app/core/config.py': r'''
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    app_env: str = 'dev'
    public_base_url: str = ''
    internal_base_url: str = 'http://10.8.0.1:8140'

    database_url: str = 'sqlite+aiosqlite:///./pokerbot_stage.db'
    redis_url: str | None = None

    telegram_bot_token: str | None = None
    telegram_webhook_secret: str | None = None

    max_bot_token: str | None = None
    max_webhook_secret: str | None = None

    admin_token: str | None = None
    boss_platform: str | None = None
    boss_platform_user_id: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
'''.strip() + '\n',

'app/core/security.py': r'''
import hashlib
import hmac
import time
from urllib.parse import parse_qsl, unquote

MAX_AUTH_AGE_SECONDS = 86400


class AuthError(ValueError):
    pass


def constant_eq(a: str, b: str) -> bool:
    return hmac.compare_digest((a or '').encode(), (b or '').encode())


def validate_shared_token(header_value: str | None, expected: str | None) -> bool:
    if not expected:
        return True
    return constant_eq(header_value or '', expected)


def validate_webapp_init_data(init_data: str, bot_token: str, *, max_age_seconds: int = MAX_AUTH_AGE_SECONDS) -> dict[str, str]:
    if not init_data or not bot_token:
        raise AuthError('missing init data or bot token')

    pairs = parse_qsl(init_data, keep_blank_values=True, strict_parsing=False)
    if sum(1 for k, _ in pairs if k == 'hash') != 1:
        raise AuthError('bad hash count')

    incoming_hash = next(v for k, v in pairs if k == 'hash')
    cleaned: list[tuple[str, str]] = []
    for key, value in pairs:
        if key == 'hash':
            continue
        cleaned.append((key, unquote(value)))

    cleaned.sort(key=lambda item: item[0])
    check_string = '\n'.join(f'{k}={v}' for k, v in cleaned)

    secret_key = hmac.new(b'WebAppData', bot_token.encode(), hashlib.sha256).digest()
    calculated = hmac.new(secret_key, check_string.encode(), hashlib.sha256).hexdigest()

    if not constant_eq(calculated, incoming_hash):
        raise AuthError('bad signature')

    data = dict(cleaned)
    auth_date = data.get('auth_date')
    if auth_date and max_age_seconds > 0:
        try:
            if time.time() - int(auth_date) > max_age_seconds:
                raise AuthError('init data expired')
        except ValueError as exc:
            raise AuthError('bad auth_date') from exc

    return data
'''.strip() + '\n',

'app/db/base.py': r'''
from collections.abc import AsyncGenerator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

settings = get_settings()
engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


class Base(DeclarativeBase):
    pass


async def init_db() -> None:
    from app.db import models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text('SELECT 1'))


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session
'''.strip() + '\n',

'app/db/models.py': r'''
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = 'users'

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    username: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    is_blocked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    identities: Mapped[list['PlatformIdentity']] = relationship(back_populates='user')


class PlatformIdentity(Base):
    __tablename__ = 'platform_identities'
    __table_args__ = (UniqueConstraint('platform', 'platform_user_id', name='uq_platform_user'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True, nullable=False)
    platform: Mapped[str] = mapped_column(String(40), nullable=False)
    platform_user_id: Mapped[str] = mapped_column(String(128), nullable=False)
    username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    raw_profile: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user: Mapped[User] = relationship(back_populates='identities')


class Chat(Base):
    __tablename__ = 'chats'
    __table_args__ = (UniqueConstraint('platform', 'platform_chat_id', name='uq_platform_chat'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    platform: Mapped[str] = mapped_column(String(40), nullable=False)
    platform_chat_id: Mapped[str] = mapped_column(String(128), nullable=False)
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    chat_type: Mapped[str] = mapped_column(String(40), default='private', nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)


class ChatMembership(Base):
    __tablename__ = 'chat_memberships'
    __table_args__ = (UniqueConstraint('chat_id', 'user_id', name='uq_chat_user'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    chat_id: Mapped[int] = mapped_column(ForeignKey('chats.id'), index=True, nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True, nullable=False)
    role: Mapped[str] = mapped_column(String(40), default='member', nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class ScoreLedger(Base):
    __tablename__ = 'score_ledger'
    __table_args__ = (
        Index('ix_score_scope_user', 'scope', 'user_id'),
        Index('ix_score_scope_chat', 'scope', 'chat_id'),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True, nullable=False)
    chat_id: Mapped[int | None] = mapped_column(ForeignKey('chats.id'), index=True, nullable=True)
    platform: Mapped[str] = mapped_column(String(40), nullable=False)
    scope: Mapped[str] = mapped_column(String(40), nullable=False)
    delta: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(String(255), nullable=False)
    source: Mapped[str] = mapped_column(String(80), default='system', nullable=False)
    meta: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class Achievement(Base):
    __tablename__ = 'achievements'

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, default='', nullable=False)
    rule: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class UserAchievement(Base):
    __tablename__ = 'user_achievements'
    __table_args__ = (UniqueConstraint('user_id', 'achievement_id', name='uq_user_achievement'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True, nullable=False)
    achievement_id: Mapped[int] = mapped_column(ForeignKey('achievements.id'), index=True, nullable=False)
    awarded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class Setting(Base):
    __tablename__ = 'settings'

    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    value: Mapped[dict] = mapped_column(JSON, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)


class AdminAuditLog(Base):
    __tablename__ = 'admin_audit_log'

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    actor: Mapped[str] = mapped_column(String(255), default='system', nullable=False)
    action: Mapped[str] = mapped_column(String(120), nullable=False)
    target: Mapped[str | None] = mapped_column(String(255), nullable=True)
    meta: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
'''.strip() + '\n',

'app/db/repositories.py': r'''
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Achievement, AdminAuditLog, Chat, PlatformIdentity, ScoreLedger, Setting, User
from app.game.achievements import ACHIEVEMENTS
from app.game.cards import COMBO_POINTS, PHRASES


async def seed_defaults(db: AsyncSession) -> None:
    for item in ACHIEVEMENTS:
        existing = await db.scalar(select(Achievement).where(Achievement.code == item['code']))
        if not existing:
            db.add(Achievement(**item))

    settings = {
        'combo_points': COMBO_POINTS,
        'combo_phrases': PHRASES,
        'miniapp_holdem': {'starting_bank': 20000, 'small_blind': 50, 'big_blind': 100, 'max_players': 9},
        'duel': {'daily_limit': 1, 'match_timeout_seconds': 60},
    }
    for key, value in settings.items():
        existing = await db.scalar(select(Setting).where(Setting.key == key))
        if not existing:
            db.add(Setting(key=key, value=value))

    db.add(AdminAuditLog(actor='system', action='seed_defaults', target='settings'))
    await db.commit()


async def get_or_create_user(
    db: AsyncSession,
    *,
    platform: str,
    platform_user_id: str,
    username: str | None = None,
    display_name: str | None = None,
    raw_profile: dict | None = None,
) -> User:
    identity = await db.scalar(
        select(PlatformIdentity).where(
            PlatformIdentity.platform == platform,
            PlatformIdentity.platform_user_id == platform_user_id,
        )
    )
    if identity:
        user = await db.get(User, identity.user_id)
        assert user is not None
        return user

    user = User(username=username, display_name=display_name or username)
    db.add(user)
    await db.flush()
    db.add(
        PlatformIdentity(
            user_id=user.id,
            platform=platform,
            platform_user_id=platform_user_id,
            username=username,
            display_name=display_name,
            raw_profile=raw_profile,
        )
    )
    await db.commit()
    await db.refresh(user)
    return user


async def get_or_create_chat(
    db: AsyncSession,
    *,
    platform: str,
    platform_chat_id: str,
    title: str | None = None,
    chat_type: str = 'private',
) -> Chat:
    chat = await db.scalar(
        select(Chat).where(Chat.platform == platform, Chat.platform_chat_id == platform_chat_id)
    )
    if chat:
        return chat
    chat = Chat(platform=platform, platform_chat_id=platform_chat_id, title=title, chat_type=chat_type)
    db.add(chat)
    await db.commit()
    await db.refresh(chat)
    return chat


async def add_score(
    db: AsyncSession,
    *,
    user_id: int,
    platform: str,
    delta: int,
    scope: str,
    reason: str,
    chat_id: int | None = None,
    source: str = 'system',
    meta: dict | None = None,
) -> None:
    db.add(
        ScoreLedger(
            user_id=user_id,
            chat_id=chat_id,
            platform=platform,
            delta=delta,
            scope=scope,
            reason=reason,
            source=source,
            meta=meta,
        )
    )
    await db.commit()


async def leaderboard(db: AsyncSession, *, scope: str, chat_id: int | None = None, limit: int = 20) -> list[dict]:
    stmt = (
        select(User.id, User.username, User.display_name, func.coalesce(func.sum(ScoreLedger.delta), 0).label('score'))
        .join(ScoreLedger, ScoreLedger.user_id == User.id)
        .where(ScoreLedger.scope == scope)
        .group_by(User.id)
        .order_by(func.sum(ScoreLedger.delta).desc())
        .limit(limit)
    )
    if chat_id is not None:
        stmt = stmt.where(ScoreLedger.chat_id == chat_id)
    rows = (await db.execute(stmt)).all()
    return [
        {'user_id': r.id, 'username': r.username, 'display_name': r.display_name, 'score': int(r.score or 0)}
        for r in rows
    ]


async def counts(db: AsyncSession) -> dict:
    return {
        'users': int(await db.scalar(select(func.count(User.id))) or 0),
        'identities': int(await db.scalar(select(func.count(PlatformIdentity.id))) or 0),
        'chats': int(await db.scalar(select(func.count(Chat.id))) or 0),
        'score_entries': int(await db.scalar(select(func.count(ScoreLedger.id))) or 0),
        'achievements': int(await db.scalar(select(func.count(Achievement.id))) or 0),
    }
'''.strip() + '\n',

'app/game/cards.py': r'''
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from itertools import combinations
from random import SystemRandom

SUITS = ('♠', '♥', '♦', '♣')
RANKS = ('2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A')
RANK_VALUE = {rank: idx + 2 for idx, rank in enumerate(RANKS)}

COMBO_POINTS = {
    'Старшая карта': 0,
    'Пара': 10,
    'Две пары': 20,
    'Сет': 30,
    'Стрит': 40,
    'Флеш': 50,
    'Фул-хаус': 60,
    'Каре': 80,
    'Стрит-флеш': 100,
    'Роял-флеш': 150,
}
COMBO_RANK = {name: idx for idx, name in enumerate(COMBO_POINTS)}

PHRASES = {
    'Старшая карта': 'Если ты с этим пришёл за стол — лучше бы пришёл с бутылкой.',
    'Пара': 'Пара? В этих краях даже койоты ходят парами. Никого не впечатлит.',
    'Две пары': 'Две пары — как два зуба после драки. Лучше, чем ничего, но мало.',
    'Сет': 'Сет? Похоже, тебе повезло, как тому, кто нашёл три песо в навозе.',
    'Стрит': 'Выражаясь нашим языком — улица. И по ней ты идёшь один.',
    'Флеш': 'Один цвет, как нефть или кровь на рубашке. Надо играть жёстко.',
    'Фул-хаус': 'Фул-хаус? Это когда в салуне и стреляют, и плачут, а ты смеёшься.',
    'Каре': 'Четыре карты — или четыре стакана виски. В любом случае, кто-то упадёт.',
    'Стрит-флеш': 'Ты не просто игрок. Ты гроза салуна.',
    'Роял-флеш': 'Закрой стол. Этому ковбою больше нечего доказывать.',
}

_rng = SystemRandom()


@dataclass(frozen=True)
class HandResult:
    cards: tuple[str, ...]
    name: str
    points: int
    rank: int
    tiebreaker: tuple[int, ...]

    def beats(self, other: 'HandResult') -> int:
        left = (self.rank, self.tiebreaker)
        right = (other.rank, other.tiebreaker)
        return (left > right) - (left < right)


def new_deck() -> list[str]:
    return [f'{s}{r}' for s in SUITS for r in RANKS]


def shuffle_deck(deck: list[str] | None = None) -> list[str]:
    cards = list(deck or new_deck())
    _rng.shuffle(cards)
    return cards


def parse_card(card: str) -> tuple[str, str, int]:
    cleaned = card.replace('\ufe0f', '').strip()
    suit = cleaned[0]
    rank = cleaned[1:]
    if suit not in SUITS or rank not in RANK_VALUE:
        raise ValueError(f'bad card: {card}')
    return suit, rank, RANK_VALUE[rank]


def _straight_high(values: list[int]) -> int | None:
    unique = sorted(set(values))
    if unique == [2, 3, 4, 5, 14]:
        return 5
    if len(unique) == 5 and unique[-1] - unique[0] == 4:
        return unique[-1]
    return None


def evaluate_five(cards: list[str] | tuple[str, ...]) -> HandResult:
    if len(cards) != 5:
        raise ValueError('evaluate_five requires exactly 5 cards')
    parsed = [parse_card(c) for c in cards]
    suits = [p[0] for p in parsed]
    values = [p[2] for p in parsed]
    counts = Counter(values)
    groups = sorted(counts.items(), key=lambda item: (-item[1], -item[0]))
    flush = len(set(suits)) == 1
    straight_high = _straight_high(values)

    if flush and straight_high == 14:
        name, tiebreaker = 'Роял-флеш', (14,)
    elif flush and straight_high:
        name, tiebreaker = 'Стрит-флеш', (straight_high,)
    elif [c for _, c in groups] == [4, 1]:
        name, tiebreaker = 'Каре', tuple(v for v, c in groups for _ in range(c))
    elif [c for _, c in groups] == [3, 2]:
        name, tiebreaker = 'Фул-хаус', tuple(v for v, c in groups for _ in range(c))
    elif flush:
        name, tiebreaker = 'Флеш', tuple(sorted(values, reverse=True))
    elif straight_high:
        name, tiebreaker = 'Стрит', (straight_high,)
    elif [c for _, c in groups] == [3, 1, 1]:
        name, tiebreaker = 'Сет', tuple(v for v, c in groups for _ in range(c))
    elif [c for _, c in groups] == [2, 2, 1]:
        name, tiebreaker = 'Две пары', tuple(v for v, c in groups for _ in range(c))
    elif [c for _, c in groups] == [2, 1, 1, 1]:
        name, tiebreaker = 'Пара', tuple(v for v, c in groups for _ in range(c))
    else:
        name, tiebreaker = 'Старшая карта', tuple(sorted(values, reverse=True))

    return HandResult(tuple(cards), name, COMBO_POINTS[name], COMBO_RANK[name], tiebreaker)


def best_of_seven(table_cards: list[str], player_hand: list[str]) -> HandResult:
    cards = table_cards + player_hand
    if len(cards) < 5:
        raise ValueError('need at least 5 cards')
    return max((evaluate_five(combo) for combo in combinations(cards, 5)), key=lambda r: (r.rank, r.tiebreaker))


def deal_classic() -> tuple[list[str], list[str]]:
    deck = shuffle_deck()
    return deck[:5], deck[5:]


def deal_holdem_duel() -> tuple[list[str], list[str], list[str], list[str]]:
    deck = shuffle_deck()
    return deck[:5], deck[5:7], deck[7:9], deck[9:]


def format_cards(cards: list[str] | tuple[str, ...]) -> str:
    return ' '.join(cards)
'''.strip() + '\n',

'app/game/scoring.py': r'''
from __future__ import annotations

from dataclasses import dataclass

from app.game.cards import HandResult


@dataclass(frozen=True)
class DuelScore:
    winner: str | None
    loser: str | None
    delta_a: int
    delta_b: int
    phrase: str


def score_duel(a_id: str, a: HandResult, b_id: str, b: HandResult) -> DuelScore:
    cmp = a.beats(b)
    if cmp == 0:
        return DuelScore(None, None, 5, 5, '🤝 Разошлись миром!')
    if cmp > 0:
        winner, loser, win_hand, lose_hand = a_id, b_id, a, b
    else:
        winner, loser, win_hand, lose_hand = b_id, a_id, b, a
    diff = win_hand.rank - lose_hand.rank
    if diff == 0:
        win_pts, lose_pts, phrase = 5, 0, 'Равная битва, но победитель должен быть один'
    elif diff == 1:
        win_pts, lose_pts, phrase = 10, -5, 'На тоненького, но победа есть победа!'
    elif diff == 2:
        win_pts, lose_pts, phrase = 15, -5, 'Впечатляющая победа!'
    elif diff == 3:
        win_pts, lose_pts, phrase = 20, -10, 'Всегда на несколько шагов впереди!'
    elif diff == 4:
        win_pts, lose_pts, phrase = 25, -10, 'Разгромная победа!'
    else:
        win_pts, lose_pts, phrase = 30, -15, 'Без шансов! Убийственный переезд!'
    return DuelScore(winner, loser, win_pts if winner == a_id else lose_pts, win_pts if winner == b_id else lose_pts, phrase)
'''.strip() + '\n',

'app/game/achievements.py': r'''
ACHIEVEMENTS = [
    {'code': 'first_blood', 'title': 'Первый выстрел', 'description': 'Сыграть первую игру'},
    {'code': 'pair_hunter', 'title': 'Охотник за парами', 'description': 'Выбить пару 10 раз'},
    {'code': 'straight_road', 'title': 'Дорога через салун', 'description': 'Собрать стрит'},
    {'code': 'flush_rider', 'title': 'Всадник флеша', 'description': 'Собрать флеш'},
    {'code': 'royal_legend', 'title': 'Легенда стола', 'description': 'Собрать роял-флеш'},
    {'code': 'duelist', 'title': 'Дуэлянт', 'description': 'Победить в первой дуэли'},
]
'''.strip() + '\n',

'app/api/health.py': r'''
from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import get_db

router = APIRouter()


@router.get('/health')
async def health():
    return {'status': 'healthy', 'service': 'poker-bot', 'version': '0.2.0'}


@router.get('/ready')
async def ready(db: AsyncSession = Depends(get_db)):
    await db.execute(text('SELECT 1'))
    return {'ok': True, 'db': 'ready'}
'''.strip() + '\n',

'app/api/game.py': r'''
from fastapi import APIRouter

from app.game.cards import PHRASES, best_of_seven, deal_classic, deal_holdem_duel, evaluate_five
from app.game.scoring import score_duel

router = APIRouter(prefix='/api/game')


@router.get('/classic/sample')
async def classic_sample():
    hand, _deck = deal_classic()
    result = evaluate_five(hand)
    return {'hand': hand, 'combo': result.name, 'points': result.points, 'phrase': PHRASES[result.name]}


@router.get('/holdem/duel-sample')
async def holdem_duel_sample():
    table, hand_a, hand_b, _deck = deal_holdem_duel()
    result_a = best_of_seven(table, hand_a)
    result_b = best_of_seven(table, hand_b)
    score = score_duel('a', result_a, 'b', result_b)
    return {
        'table': table,
        'a': {'hand': hand_a, 'combo': result_a.name, 'points': result_a.points, 'delta': score.delta_a},
        'b': {'hand': hand_b, 'combo': result_b.name, 'points': result_b.points, 'delta': score.delta_b},
        'winner': score.winner,
        'phrase': score.phrase,
    }
'''.strip() + '\n',

'app/api/leaderboards.py': r'''
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import get_db
from app.db.repositories import leaderboard

router = APIRouter(prefix='/api/leaderboards')


@router.get('/global')
async def global_leaderboard(limit: int = Query(default=20, ge=1, le=100), db: AsyncSession = Depends(get_db)):
    return {'items': await leaderboard(db, scope='global', limit=limit)}


@router.get('/duel')
async def duel_leaderboard(limit: int = Query(default=20, ge=1, le=100), db: AsyncSession = Depends(get_db)):
    return {'items': await leaderboard(db, scope='duel', limit=limit)}


@router.get('/chat/{chat_id}')
async def chat_leaderboard(chat_id: int, limit: int = Query(default=20, ge=1, le=100), db: AsyncSession = Depends(get_db)):
    return {'items': await leaderboard(db, scope='chat', chat_id=chat_id, limit=limit)}
'''.strip() + '\n',

'app/api/admin.py': r'''
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import validate_shared_token
from app.db.base import get_db
from app.db.models import Achievement, Chat, Setting, User
from app.db.repositories import add_score, counts, get_or_create_user, seed_defaults

router = APIRouter(prefix='/admin')


def require_admin(x_admin_token: str | None = Header(default=None)) -> None:
    settings = get_settings()
    if settings.admin_token and not validate_shared_token(x_admin_token, settings.admin_token):
        raise HTTPException(status_code=401, detail='admin token required')


class DemoUserIn(BaseModel):
    platform: str = 'telegram'
    platform_user_id: str
    username: str | None = None
    display_name: str | None = None


class ScoreAdjustIn(BaseModel):
    user_id: int
    platform: str = 'telegram'
    delta: int = Field(ge=-1_000_000, le=1_000_000)
    scope: str = 'global'
    reason: str = 'admin_adjust'
    chat_id: int | None = None


class SettingIn(BaseModel):
    value: dict


@router.get('/health')
async def admin_health(_: None = Depends(require_admin)):
    return {'ok': True, 'admin': True}


@router.post('/seed')
async def admin_seed(_: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    await seed_defaults(db)
    return {'ok': True}


@router.get('/summary')
async def admin_summary(_: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    return await counts(db)


@router.post('/demo-user')
async def admin_demo_user(payload: DemoUserIn, _: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    user = await get_or_create_user(
        db,
        platform=payload.platform,
        platform_user_id=payload.platform_user_id,
        username=payload.username,
        display_name=payload.display_name,
    )
    return {'ok': True, 'user_id': user.id}


@router.post('/score/adjust')
async def admin_adjust_score(payload: ScoreAdjustIn, _: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    user = await db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=404, detail='user not found')
    await add_score(
        db,
        user_id=payload.user_id,
        platform=payload.platform,
        delta=payload.delta,
        scope=payload.scope,
        reason=payload.reason,
        chat_id=payload.chat_id,
        source='admin',
    )
    return {'ok': True}


@router.get('/users')
async def admin_users(_: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(User).order_by(User.id.desc()).limit(100))).scalars().all()
    return {'items': [{'id': u.id, 'username': u.username, 'display_name': u.display_name, 'is_blocked': u.is_blocked} for u in rows]}


@router.get('/chats')
async def admin_chats(_: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(Chat).order_by(Chat.id.desc()).limit(100))).scalars().all()
    return {'items': [{'id': c.id, 'platform': c.platform, 'platform_chat_id': c.platform_chat_id, 'title': c.title, 'chat_type': c.chat_type} for c in rows]}


@router.get('/achievements')
async def admin_achievements(_: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(Achievement).order_by(Achievement.id))).scalars().all()
    return {'items': [{'code': a.code, 'title': a.title, 'description': a.description, 'active': a.is_active} for a in rows]}


@router.get('/settings')
async def admin_settings(_: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(Setting).order_by(Setting.key))).scalars().all()
    return {'items': [{'key': s.key, 'value': s.value} for s in rows]}


@router.put('/settings/{key}')
async def admin_put_setting(key: str, payload: SettingIn, _: None = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    setting = await db.get(Setting, key)
    if setting:
        setting.value = payload.value
    else:
        db.add(Setting(key=key, value=payload.value))
    await db.commit()
    return {'ok': True}
'''.strip() + '\n',

'app/api/miniapp.py': r'''
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.config import get_settings
from app.core.security import AuthError, validate_webapp_init_data
from app.game.achievements import ACHIEVEMENTS

router = APIRouter(prefix='/api/miniapp')


class LoginIn(BaseModel):
    platform: str
    init_data: str


@router.post('/login')
async def miniapp_login(payload: LoginIn):
    settings = get_settings()
    platform = payload.platform.lower()
    if platform == 'telegram':
        token = settings.telegram_bot_token
    elif platform == 'max':
        token = settings.max_bot_token
    else:
        token = None
    if not token:
        raise HTTPException(status_code=400, detail='platform token not configured')
    try:
        data = validate_webapp_init_data(payload.init_data, token)
    except AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    return {'ok': True, 'platform': platform, 'profile': data}


@router.get('/achievements')
async def achievements():
    return {'items': ACHIEVEMENTS}
'''.strip() + '\n',

'app/api/webhooks.py': r'''
from fastapi import APIRouter, Request

router = APIRouter(prefix='/webhooks')


@router.post('/telegram')
async def telegram_webhook(request: Request):
    update = await request.json()
    return {'ok': True, 'platform': 'telegram', 'accepted': bool(update)}


@router.post('/max')
async def max_webhook(request: Request):
    update = await request.json()
    return {'ok': True, 'platform': 'max', 'accepted': bool(update)}
'''.strip() + '\n',

'app/main.py': r'''
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.api.admin import router as admin_router
from app.api.game import router as game_router
from app.api.health import router as health_router
from app.api.leaderboards import router as leaderboards_router
from app.api.miniapp import router as miniapp_router
from app.api.webhooks import router as webhooks_router
from app.db.base import init_db
from app.db.repositories import seed_defaults
from app.db.base import SessionLocal

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / 'static'


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    async with SessionLocal() as db:
        await seed_defaults(db)
    yield


app = FastAPI(title='Poker Bot API', version='0.2.0', lifespan=lifespan)

app.include_router(health_router)
app.include_router(webhooks_router)
app.include_router(game_router)
app.include_router(leaderboards_router)
app.include_router(miniapp_router)
app.include_router(admin_router)

app.mount('/static', StaticFiles(directory=STATIC_DIR), name='static')


@app.get('/')
async def root():
    return {'ok': True, 'service': 'poker-bot', 'version': '0.2.0'}


@app.get('/miniapp')
async def miniapp():
    return FileResponse(STATIC_DIR / 'miniapp' / 'index.html')
'''.strip() + '\n',

'app/static/miniapp/index.html': r'''
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Poker Saloon</title>
  <style>
    :root{--bg:#140b09;--card:#25110d;--line:#7a4d24;--text:#f7e5bf;--gold:#d19845;}
    *{box-sizing:border-box} body{margin:0;background:radial-gradient(circle at top,#3d2116,var(--bg));color:var(--text);font-family:system-ui,Arial,sans-serif;}
    .wrap{max-width:980px;margin:0 auto;padding:24px;}
    .card{border:1px solid var(--line);border-radius:24px;padding:24px;background:linear-gradient(135deg,#25110d,#160b08);box-shadow:0 20px 60px #0009;}
    h1{font-size:34px;margin:0 0 10px}.muted{opacity:.78}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;margin-top:20px;}
    .tile{border:1px solid #8b6234;border-radius:18px;padding:16px;background:#0004;min-height:92px}.big{font-size:26px;font-weight:800;color:var(--gold)}
  </style>
</head>
<body>
  <main class="wrap">
    <section class="card">
      <h1>Poker Saloon</h1>
      <p class="muted">Личный кабинет игрока: очки, дуэли, достижения, мировой рейтинг.</p>
      <div class="grid">
        <div class="tile"><div class="big">20 000</div><div>стартовый банк Mini App</div></div>
        <div class="tile"><div class="big">50/100</div><div>лимит holdem</div></div>
        <div class="tile"><div class="big">9-max</div><div>будущие комнаты</div></div>
        <div class="tile"><div class="big">Admin</div><div>правила, очки, фразы</div></div>
      </div>
    </section>
  </main>
</body>
</html>
'''.strip() + '\n',

'tests/test_cards.py': r'''
from app.game.cards import best_of_seven, evaluate_five
from app.game.scoring import score_duel


def test_royal_flush():
    result = evaluate_five(['♠10', '♠J', '♠Q', '♠K', '♠A'])
    assert result.name == 'Роял-флеш'
    assert result.points == 150


def test_wheel_straight():
    result = evaluate_five(['♠A', '♥2', '♦3', '♣4', '♠5'])
    assert result.name == 'Стрит'
    assert result.tiebreaker == (5,)


def test_best_of_seven_pair_vs_high():
    result = best_of_seven(['♠2', '♥5', '♦9', '♣K', '♠A'], ['♥A', '♦3'])
    assert result.name == 'Пара'


def test_duel_scoring_by_category_diff():
    a = evaluate_five(['♠10', '♠J', '♠Q', '♠K', '♠A'])
    b = evaluate_five(['♠2', '♥2', '♦7', '♣9', '♠K'])
    score = score_duel('a', a, 'b', b)
    assert score.winner == 'a'
    assert score.delta_a == 30
    assert score.delta_b == -15
'''.strip() + '\n',
}

for path, content in files.items():
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')

print(f'WROTE {len(files)} files into {root}')
PY

python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"

git add .
git commit -m "Add database admin and leaderboard stage 2" || true
git push -u origin main

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health

curl -s --max-time 5 http://10.8.0.1:8140/health && echo
curl -s --max-time 5 http://10.8.0.1:8140/ready && echo
curl -s --max-time 5 http://10.8.0.1:8140/api/game/classic/sample && echo
curl -s --max-time 5 http://10.8.0.1:8140/api/leaderboards/global && echo

echo "===== POKER BOT STAGE 2 DONE ====="
