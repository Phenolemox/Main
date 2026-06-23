"""Расчёт количества предлагаемых и выбираемых сфер за ход."""
from __future__ import annotations

import random

from game.balloon_config import BALLOON_TYPES, COLOR_EMOJIS


def calculate_offer_and_pick(collection: list[str]) -> tuple[int, int]:
    """Возвращает (сколько предложить, сколько можно выбрать).

    Бонусы дают ТОЛЬКО триплеты: синие триплеты увеличивают предложение,
    красные триплеты увеличивают количество выбора.
    """
    blue_total = collection.count(BALLOON_TYPES["blue"]["emoji"])
    red_total = collection.count(BALLOON_TYPES["red"]["emoji"])

    blue_triplets = blue_total // 3
    red_triplets = red_total // 3

    offer_num = 6 + blue_triplets
    pick_num = 3 + red_triplets
    return offer_num, pick_num


def make_offer(offer_num: int) -> list[str]:
    """Генерирует случайное предложение сфер заданного размера."""
    return [random.choice(COLOR_EMOJIS) for _ in range(offer_num)]


def make_initial_balls(count: int = 5) -> list[str]:
    """Стартовый набор сфер игрока."""
    return [random.choice(COLOR_EMOJIS) for _ in range(count)]
