"""Подсчёт очков и разбор собранной коллекции сфер."""
from __future__ import annotations

import random
from collections import Counter

from game.balloon_config import (
    ALL_COLORS_BONUS,
    BALLOON_TYPES,
    EMOJI_TO_COLOR,
)


def pluralize(number: int, singular: str, few: str, many: str) -> str:
    """Русские склонения для чисел (1 сфера / 2 сферы / 5 сфер)."""
    if 11 <= number % 100 <= 14:
        return many
    if number % 10 == 1:
        return singular
    if 2 <= number % 10 <= 4:
        return few
    return many


def split_color(color: str, total: int) -> tuple[int, int, int]:
    """Разбивает количество сфер цвета на (нионсы, триплеты, одиночные).

    green: 9 = нионс, 3 = триплет; gold: всегда одиночные; остальные: 3 = триплет.
    """
    super_triplets = triplets = singles = 0
    if color == "green":
        super_triplets = total // 9
        total %= 9
        triplets = total // 3
        singles = total % 3
    elif color == "gold":
        singles = total
    else:
        triplets = total // 3
        singles = total % 3
    return super_triplets, triplets, singles


def breakdown_collection(collection: list[str]) -> dict:
    """Возвращает агрегаты по коллекции для записи в БД и проверки достижений."""
    counts = Counter(collection)
    sphere_counts = {color: 0 for color in BALLOON_TYPES}
    triplet_counts = {color: 0 for color in BALLOON_TYPES}
    nions_counts = {color: 0 for color in BALLOON_TYPES}
    triplets_total = 0
    nions_total = 0

    for color, config in BALLOON_TYPES.items():
        total = counts.get(config["emoji"], 0)
        supers, triplets, singles = split_color(color, total)
        nions_counts[color] = supers
        triplet_counts[color] = triplets
        sphere_counts[color] = singles
        triplets_total += triplets
        nions_total += supers

    return {
        "sphere_counts": sphere_counts,
        "triplet_counts": triplet_counts,
        "nions_counts": nions_counts,
        "triplets_total": triplets_total,
        "nions_total": nions_total,
    }


def display_balloon_collection(collection: list[str]) -> str:
    """Текстовое отображение собранных сфер между раундами."""
    count = Counter(collection)
    details = []
    for emoji, color in EMOJI_TO_COLOR.items():
        total = count.get(emoji, 0)
        if total == 0:
            continue
        supers, triplets, singles = split_color(color, total)
        parts = []
        if supers:
            parts.append(f"{supers} {pluralize(supers, 'нионс', 'нионса', 'нионсов')}")
        if triplets:
            parts.append(f"{triplets} {pluralize(triplets, 'триплет', 'триплета', 'триплетов')}")
        if singles:
            parts.append(f"{singles} {pluralize(singles, 'сфера', 'сферы', 'сфер')}")
        details.append(f"{emoji} — собрано " + ", ".join(parts))
    return "🧮 <b>Собранные сферы:</b>\n" + "\n".join(details)


def calculate_score(collection: list[str]) -> tuple[str, int]:
    """Итоговый подсчёт очков по коллекции. Возвращает (текст, всего очков)."""
    total_points = 0
    details = []
    count = Counter(collection)
    collected_colors = 0

    for emoji, color in EMOJI_TO_COLOR.items():
        config = BALLOON_TYPES[color]
        total = count.get(emoji, 0)
        if total == 0:
            continue
        collected_colors += 1
        supers, triplets, singles = split_color(color, total)

        if supers and config.get("super_triplet_points"):
            score = supers * config["super_triplet_points"]
            details.append(
                f"{emoji} — {supers} {pluralize(supers, 'нионс', 'нионса', 'нионсов')}: +{score} очков"
            )
            total_points += score

        if triplets:
            if "triplet_points_range" in config:
                triplet_points = sum(random.randint(*config["triplet_points_range"]) for _ in range(triplets))
            else:
                triplet_points = triplets * config["triplet_points"]
            details.append(
                f"{emoji} — {triplets} {pluralize(triplets, 'триплет', 'триплета', 'триплетов')}: +{triplet_points} очков"
            )
            total_points += triplet_points

        if singles:
            if "single_points_range" in config:
                single_points = sum(random.randint(*config["single_points_range"]) for _ in range(singles))
            else:
                single_points = singles * config["single_points"]
            details.append(
                f"{emoji} — {singles} {pluralize(singles, 'сфера', 'сферы', 'сфер')}: +{single_points} очков"
            )
            total_points += single_points

    if collected_colors == len(BALLOON_TYPES):
        details.append(f"\n💎 Бонус за все цвета: +{ALL_COLORS_BONUS} очков")
        total_points += ALL_COLORS_BONUS

    details.append(f"<b>\n🎖️ Итого очков: {total_points}</b>")
    return "\n".join(details), total_points
