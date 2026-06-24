from __future__ import annotations

import random
from dataclasses import dataclass
from typing import Any

FIGHT_STATS = ("physical_power", "magic", "speed", "intelligence")
TRAINABLE_STATS = ("physical_power", "magic", "speed", "intelligence", "media")
VALID_CONTRACTS = ("standard", "grateful", "deadly")
VALID_EVENT_STATUSES = ("draft", "announced", "bets_open", "bets_closed", "completed")
VALID_FIGHT_TYPES = ("normal", "deadly", "exhibition", "partner")


class EngineError(ValueError):
    """Controlled game-rule error."""


@dataclass(frozen=True)
class FightResult:
    winner_id: int
    loser_id: int
    probability_a: float
    method: str
    round: int


def fighter_score(fighter: dict[str, Any]) -> float:
    combat_score = sum(float(fighter.get(stat, 0)) for stat in FIGHT_STATS)
    media_bonus = float(fighter.get("media", 0)) * 0.2
    rarity_bonus = {
        "Common": 0.0,
        "Rare": 0.5,
        "Epic": 1.0,
        "Legendary": 1.5,
        "Mythic": 2.0,
    }.get(str(fighter.get("rarity", "Common")), 0.0)
    return max(1.0, combat_score + media_bonus + rarity_bonus)


def winner_probability_a(
    fighter_a: dict[str, Any],
    fighter_b: dict[str, Any],
    random_factor: float,
    skill_factor: float,
) -> float:
    score_a = fighter_score(fighter_a)
    score_b = fighter_score(fighter_b)
    total_score = score_a + score_b
    skill_probability = 0.5 if total_score <= 0 else score_a / total_score
    factor_sum = max(0.01, random_factor + skill_factor)
    probability = ((0.5 * random_factor) + (skill_probability * skill_factor)) / factor_sum
    return max(0.05, min(0.95, probability))


def validate_contract(contract: str) -> str:
    if contract not in VALID_CONTRACTS:
        raise EngineError(f"Недопустимый контракт: {contract}")
    return contract


def validate_event_status(status: str) -> str:
    if status not in VALID_EVENT_STATUSES:
        raise EngineError(f"Недопустимый статус события: {status}")
    return status


def validate_fight_type(fight_type: str, fighter_a: dict[str, Any], fighter_b: dict[str, Any]) -> str:
    if fight_type not in VALID_FIGHT_TYPES:
        raise EngineError(f"Недопустимый тип боя: {fight_type}")
    if fight_type == "deadly":
        if fighter_a.get("contract") != "deadly" or fighter_b.get("contract") != "deadly":
            raise EngineError("Смертельный бой запрещён: оба бойца должны иметь смертельный контракт.")
    return fight_type


def calculate_fight(
    fighter_a: dict[str, Any],
    fighter_b: dict[str, Any],
    random_factor: float,
    skill_factor: float,
) -> FightResult:
    probability_a = winner_probability_a(fighter_a, fighter_b, random_factor, skill_factor)
    a_wins = random.random() <= probability_a
    winner = fighter_a if a_wins else fighter_b
    loser = fighter_b if a_wins else fighter_a
    method = random.choice(["KO", "TKO", "Submission", "Decision", "Arcane stoppage", "Psychic collapse"])
    round_number = random.randint(1, 5)
    return FightResult(
        winner_id=int(winner["id"]),
        loser_id=int(loser["id"]),
        probability_a=round(probability_a, 4),
        method=method,
        round=round_number,
    )


SUIT_TO_STAT = {
    "hearts": "physical_power",
    "clubs": "speed",
    "diamonds": "magic",
    "spades": "intelligence",
}

RANK_VALUES = {
    "2": 2,
    "3": 3,
    "4": 4,
    "5": 5,
    "6": 6,
    "7": 7,
    "8": 8,
    "9": 9,
    "10": 10,
    "J": 11,
    "Q": 12,
    "K": 13,
    "A": 14,
}


def build_deck() -> list[dict[str, str]]:
    return [{"rank": rank, "suit": suit} for suit in SUIT_TO_STAT for rank in RANK_VALUES]


def draw_cards(count: int, deck: list[dict[str, str]] | None = None) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    active_deck = deck[:] if deck is not None else build_deck()
    random.shuffle(active_deck)
    return active_deck[:count], active_deck[count:]


def poker_training_bonus(hand: list[dict[str, str]], board: list[dict[str, str]]) -> dict[str, Any]:
    if len(hand) != 2 or len(board) != 5:
        raise EngineError("Для финального зачёта нужны 2 карты руки и 5 карт борда.")

    cards = hand + board
    hand_ids = {(card["rank"], card["suit"]) for card in hand}
    by_rank: dict[str, list[dict[str, str]]] = {}
    by_suit: dict[str, list[dict[str, str]]] = {}

    for card in cards:
        by_rank.setdefault(card["rank"], []).append(card)
        by_suit.setdefault(card["suit"], []).append(card)

    def includes_hand(combo_cards: list[dict[str, str]]) -> bool:
        return any((card["rank"], card["suit"]) in hand_ids for card in combo_cards)

    best_name = "high_card"
    best_cards: list[dict[str, str]] = [max(hand, key=lambda c: RANK_VALUES[c["rank"]])]
    best_power = 1

    rank_groups = sorted(by_rank.items(), key=lambda item: (len(item[1]), RANK_VALUES[item[0]]), reverse=True)
    pairs = [(rank, group) for rank, group in rank_groups if len(group) == 2 and includes_hand(group)]
    triples = [(rank, group) for rank, group in rank_groups if len(group) == 3 and includes_hand(group)]
    quads = [(rank, group) for rank, group in rank_groups if len(group) == 4 and includes_hand(group)]
    flushes = [(suit, group) for suit, group in by_suit.items() if len(group) >= 5 and includes_hand(group[:5])]

    values_to_cards: dict[int, list[dict[str, str]]] = {}
    for card in cards:
        values_to_cards.setdefault(RANK_VALUES[card["rank"]], []).append(card)

    straight_cards: list[dict[str, str]] = []
    values = sorted(values_to_cards)
    for idx in range(0, max(0, len(values) - 4)):
        window = values[idx : idx + 5]
        if window[-1] - window[0] == 4 and len(window) == 5:
            candidate = [values_to_cards[value][0] for value in window]
            if includes_hand(candidate):
                straight_cards = candidate

    if quads:
        best_name, best_cards, best_power = "four_of_a_kind", quads[0][1], 8
    elif triples and pairs:
        best_name, best_cards, best_power = "full_house", triples[0][1] + pairs[0][1], 7
    elif flushes:
        suited = sorted(flushes[0][1], key=lambda c: RANK_VALUES[c["rank"]], reverse=True)[:5]
        best_name, best_cards, best_power = "flush", suited, 6
    elif straight_cards:
        best_name, best_cards, best_power = "straight", straight_cards, 5
    elif triples:
        best_name, best_cards, best_power = "three_of_a_kind", triples[0][1], 4
    elif len(pairs) >= 2:
        best_name, best_cards, best_power = "two_pair", pairs[0][1] + pairs[1][1], 3
    elif pairs:
        best_name, best_cards, best_power = "pair", pairs[0][1], 2

    stat_votes: dict[str, int] = {}
    for card in best_cards:
        if (card["rank"], card["suit"]) in hand_ids:
            stat = SUIT_TO_STAT[card["suit"]]
            stat_votes[stat] = max(stat_votes.get(stat, 0), min(RANK_VALUES[card["rank"]], 14))

    if not stat_votes:
        top_hand_card = max(hand, key=lambda c: RANK_VALUES[c["rank"]])
        stat_votes[SUIT_TO_STAT[top_hand_card["suit"]]] = 1

    return {
        "combination": best_name,
        "bonus_power": best_power,
        "available_stats": stat_votes,
        "cards_used": best_cards,
    }
