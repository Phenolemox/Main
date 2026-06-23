"""Игровые сессии в памяти процесса (одна активная игра на пользователя)."""
from __future__ import annotations

from dataclasses import dataclass, field

from bot_config import TOTAL_ROUNDS
from game.logic import calculate_offer_and_pick, make_initial_balls, make_offer


@dataclass
class GameSession:
    chat_id: int
    private: bool
    collection: list[str] = field(default_factory=list)
    round: int = 1
    offer: list[str] = field(default_factory=list)
    pick_count: int = 3
    selected: list[int] = field(default_factory=list)

    @property
    def is_last_round(self) -> bool:
        return self.round >= TOTAL_ROUNDS

    def roll_new_offer(self) -> None:
        """Готовит предложение для текущего раунда на основе коллекции."""
        offer_num, pick_num = calculate_offer_and_pick(self.collection)
        self.offer = make_offer(offer_num)
        self.pick_count = pick_num
        self.selected = []

    def toggle(self, index: int) -> str:
        """Переключает выбор сферы. Возвращает статус: ok | full | removed."""
        if index in self.selected:
            self.selected.remove(index)
            return "removed"
        if len(self.selected) >= self.pick_count:
            return "full"
        self.selected.append(index)
        return "ok"

    def selection_complete(self) -> bool:
        return len(self.selected) == self.pick_count

    def commit_selection(self) -> None:
        """Добавляет выбранные сферы в коллекцию."""
        chosen = [self.offer[i] for i in self.selected]
        self.collection.extend(chosen)

    def advance_round(self) -> None:
        self.round += 1
        self.roll_new_offer()


_SESSIONS: dict[int, GameSession] = {}


def start_session(user_id: int, chat_id: int, private: bool) -> GameSession:
    session = GameSession(chat_id=chat_id, private=private, collection=make_initial_balls())
    session.roll_new_offer()
    _SESSIONS[user_id] = session
    return session


def get_session(user_id: int) -> GameSession | None:
    return _SESSIONS.get(user_id)


def end_session(user_id: int) -> None:
    _SESSIONS.pop(user_id, None)


def clear_chat_sessions(chat_id: int) -> None:
    for uid in [uid for uid, s in _SESSIONS.items() if s.chat_id == chat_id]:
        _SESSIONS.pop(uid, None)
