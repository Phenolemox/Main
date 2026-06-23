# Конфигурация сфер и бонусов для игры CB Balloon's

BALLOON_TYPES = {
    "blue": {
        "emoji": "🧿",
        "name": "Expansion",
        "single_points": 5,
        "triplet_points": 30,
        "super_triplet_points": None,
        "ability_threshold": 3,
        "increase_offered": True,
        "increase_chosen": False,
    },
    "red": {
        "emoji": "☄️",
        "name": "Conquest",
        "single_points": 5,
        "triplet_points": 30,
        "super_triplet_points": None,
        "ability_threshold": 3,
        "increase_offered": False,
        "increase_chosen": True,
    },
    "green": {
        "emoji": "🦠",
        "name": "Plants",
        "single_points": 3,
        "triplet_points": 20,
        "super_triplet_points": 120,
        "ability_threshold": 3,
        "increase_offered": False,
        "increase_chosen": False,
    },
    "gold": {
        "emoji": "🌕",
        "name": "Gold",
        "single_points": 8,
        "triplet_points": None,
        "super_triplet_points": None,
        "ability_threshold": None,
        "increase_offered": False,
        "increase_chosen": False,
    },
    "purple": {
        "emoji": "🔮",
        "name": "Arcane",
        "single_points_range": (1, 10),
        "triplet_points_range": (10, 50),
        "triplet_points": None,
        "super_triplet_points": None,
        "ability_threshold": None,
        "increase_offered": False,
        "increase_chosen": False,
    },
}

ALL_COLORS_BONUS = 25

# Список цветов в фиксированном порядке (используется для колонок БД и подсчётов)
COLOR_ORDER = ["blue", "red", "green", "gold", "purple"]

# Соответствие эмодзи -> цвет
EMOJI_TO_COLOR = {config["emoji"]: color for color, config in BALLOON_TYPES.items()}

# Список эмодзи для генерации предложений
COLOR_EMOJIS = [config["emoji"] for config in BALLOON_TYPES.values()]
