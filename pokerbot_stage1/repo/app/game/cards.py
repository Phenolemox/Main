from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from itertools import combinations
from random import SystemRandom

SUITS = ("♠", "♥", "♦", "♣")
RANKS = ("2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A")
RANK_VALUE = {rank: idx + 2 for idx, rank in enumerate(RANKS)}

COMBO_POINTS = {
    "Старшая карта": 0,
    "Пара": 10,
    "Две пары": 20,
    "Сет": 30,
    "Стрит": 40,
    "Флеш": 50,
    "Фул-хаус": 60,
    "Каре": 80,
    "Стрит-флеш": 100,
    "Роял-флеш": 150,
}
COMBO_RANK = {name: idx for idx, name in enumerate(COMBO_POINTS)}

PHRASES = {
    "Старшая карта": "Если ты с этим пришёл за стол — лучше бы пришёл с бутылкой.",
    "Пара": "Пара? В этих краях даже койоты ходят парами. Никого не впечатлит.",
    "Две пары": "Две пары — как два зуба после драки. Лучше, чем ничего, но мало.",
    "Сет": "Сет? Похоже, тебе повезло, как тому, кто нашёл три песо в навозе.",
    "Стрит": "Выражаясь нашим языком — улица. И по ней ты идёшь один.",
    "Флеш": "Один цвет, как нефть или кровь на рубашке. Надо играть жёстко.",
    "Фул-хаус": "Фул-хаус? Это когда в салуне и стреляют, и плачут, а ты смеёшься.",
    "Каре": "Четыре карты — или четыре стакана виски. В любом случае, кто-то упадёт.",
    "Стрит-флеш": "Ты не просто игрок. Ты гроза салуна.",
    "Роял-флеш": "Закрой стол. Этому ковбою больше нечего доказывать.",
}

_rng = SystemRandom()


@dataclass(frozen=True)
class HandResult:
    cards: tuple[str, ...]
    name: str
    points: int
    rank: int
    tiebreaker: tuple[int, ...]

    def beats(self, other: "HandResult") -> int:
        left = (self.rank, self.tiebreaker)
        right = (other.rank, other.tiebreaker)
        return (left > right) - (left < right)


def new_deck() -> list[str]:
    return [f"{s}{r}" for s in SUITS for r in RANKS]


def shuffle_deck(deck: list[str] | None = None) -> list[str]:
    cards = list(deck or new_deck())
    _rng.shuffle(cards)
    return cards


def parse_card(card: str) -> tuple[str, str, int]:
    cleaned = card.replace("\ufe0f", "").strip()
    suit = cleaned[0]
    rank = cleaned[1:]
    if suit not in SUITS or rank not in RANK_VALUE:
        raise ValueError(f"bad card: {card}")
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
        raise ValueError("evaluate_five requires exactly 5 cards")

    parsed = [parse_card(c) for c in cards]
    suits = [p[0] for p in parsed]
    values = [p[2] for p in parsed]
    counts = Counter(values)
    groups = sorted(counts.items(), key=lambda item: (-item[1], -item[0]))

    flush = len(set(suits)) == 1
    straight_high = _straight_high(values)

    if flush and straight_high == 14:
        name = "Роял-флеш"
        tiebreaker = (14,)
    elif flush and straight_high:
        name = "Стрит-флеш"
        tiebreaker = (straight_high,)
    elif [c for _, c in groups] == [4, 1]:
        name = "Каре"
        tiebreaker = tuple(v for v, c in groups for _ in range(c))
    elif [c for _, c in groups] == [3, 2]:
        name = "Фул-хаус"
        tiebreaker = tuple(v for v, c in groups for _ in range(c))
    elif flush:
        name = "Флеш"
        tiebreaker = tuple(sorted(values, reverse=True))
    elif straight_high:
        name = "Стрит"
        tiebreaker = (straight_high,)
    elif [c for _, c in groups] == [3, 1, 1]:
        name = "Сет"
        tiebreaker = tuple(v for v, c in groups for _ in range(c))
    elif [c for _, c in groups] == [2, 2, 1]:
        name = "Две пары"
        tiebreaker = tuple(v for v, c in groups for _ in range(c))
    elif [c for _, c in groups] == [2, 1, 1, 1]:
        name = "Пара"
        tiebreaker = tuple(v for v, c in groups for _ in range(c))
    else:
        name = "Старшая карта"
        tiebreaker = tuple(sorted(values, reverse=True))

    return HandResult(tuple(cards), name, COMBO_POINTS[name], COMBO_RANK[name], tiebreaker)


def best_of_seven(table_cards: list[str], player_hand: list[str]) -> HandResult:
    cards = table_cards + player_hand
    if len(cards) < 5:
        raise ValueError("need at least 5 cards")
    return max((evaluate_five(combo) for combo in combinations(cards, 5)), key=lambda r: (r.rank, r.tiebreaker))


def deal_classic() -> tuple[list[str], list[str]]:
    deck = shuffle_deck()
    return deck[:5], deck[5:]


def deal_holdem_duel() -> tuple[list[str], list[str], list[str], list[str]]:
    deck = shuffle_deck()
    return deck[:5], deck[5:7], deck[7:9], deck[9:]


def format_cards(cards: list[str] | tuple[str, ...]) -> str:
    return " ".join(cards)
