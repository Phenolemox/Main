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
        return DuelScore(None, None, 5, 5, "🤝 Разошлись миром!")

    if cmp > 0:
        winner, loser, win_hand, lose_hand = a_id, b_id, a, b
    else:
        winner, loser, win_hand, lose_hand = b_id, a_id, b, a

    diff = win_hand.rank - lose_hand.rank

    if diff == 0:
        win_pts, lose_pts, phrase = 5, 0, "Равная битва, но победитель должен быть один"
    elif diff == 1:
        win_pts, lose_pts, phrase = 10, -5, "На тоненького, но победа есть победа!"
    elif diff == 2:
        win_pts, lose_pts, phrase = 15, -5, "Впечатляющая победа!"
    elif diff == 3:
        win_pts, lose_pts, phrase = 20, -10, "Всегда на несколько шагов впереди!"
    elif diff == 4:
        win_pts, lose_pts, phrase = 25, -10, "Разгромная победа!"
    else:
        win_pts, lose_pts, phrase = 30, -15, "Без шансов! Убийственный переезд!"

    return DuelScore(
        winner=winner,
        loser=loser,
        delta_a=win_pts if winner == a_id else lose_pts,
        delta_b=win_pts if winner == b_id else lose_pts,
        phrase=phrase,
    )
