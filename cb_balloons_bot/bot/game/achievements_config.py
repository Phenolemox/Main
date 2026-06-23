# --- Файл конфигурации достижений и званий ---

# Достижения
ACHIEVEMENTS = [
    # Количество сыгранных партий
    {"id": "welcome", "name": "Добро пожаловать", "description": "Сыграть первую партию", "condition": {"games_played": 1}, "achievement_points": 10},
    {"id": "wanderer", "name": "Странник эфира", "description": "Сыграть 10 партий", "condition": {"games_played": 10}, "achievement_points": 20},
    {"id": "keeper", "name": "Хранитель пустоты", "description": "Сыграть 50 партий", "condition": {"games_played": 50}, "achievement_points": 30},
    {"id": "legend", "name": "Легенда Лимнийских путей", "description": "Сыграть 100 партий", "condition": {"games_played": 100}, "achievement_points": 50},

    # Очки за одну партию
    {"id": "spark", "name": "Искра Мощи", "description": "Набрать 100 очков за одну партию", "condition": {"max_game_points": 100}, "achievement_points": 10},
    {"id": "flame", "name": "Пламя Триумфа", "description": "Набрать 200 очков за одну партию", "condition": {"max_game_points": 200}, "achievement_points": 20},
    {"id": "vortex", "name": "Вихрь Энергии", "description": "Набрать 300 очков за одну партию", "condition": {"max_game_points": 300}, "achievement_points": 30},
    {"id": "sphere_perfect", "name": "Сфера Совершенства", "description": "Набрать 400 очков за одну партию", "condition": {"max_game_points": 400}, "achievement_points": 100},

    # Всего игровых очков
    {"id": "dust_collector", "name": "Собиратель Лунной Пыли", "description": "Набрать суммарно 1000 игровых очков", "condition": {"total_game_points": 1000}, "achievement_points": 10},
    {"id": "monochrome_prophet", "name": "Монохромный Пророк", "description": "Набрать суммарно 5000 игровых очков", "condition": {"total_game_points": 5000}, "achievement_points": 20},
    {"id": "architect_energy", "name": "Архитектор Энергетических Потоков", "description": "Набрать суммарно 10000 игровых очков", "condition": {"total_game_points": 10000}, "achievement_points": 30},
    {"id": "lord_eternal_shine", "name": "Владыка Вечного Сияния", "description": "Набрать суммарно 20000 игровых очков", "condition": {"total_game_points": 20000}, "achievement_points": 100},

    # Нионсы
    {"id": "novice_alchemist", "name": "Начинающий алхимик", "description": "Собрать 1 нионс", "condition": {"total_nions": 1}, "achievement_points": 10},
    {"id": "natural_chaos", "name": "Природный хаос", "description": "Собрать 5 нионсов", "condition": {"total_nions": 5}, "achievement_points": 20},
    {"id": "storm_toxicity", "name": "Буря токсичности", "description": "Собрать 10 нионсов", "condition": {"total_nions": 10}, "achievement_points": 50},

    # Использовать все 5 цветов за одну партию
    {"id": "chaotic_experimenter",
     "name": "Хаотичный Экспериментатор",
     "description": "Использовать все 5 цветов сфер, триплетов или нионсов за одну партию",
     "condition": {
         "blue_spheres_or_triplets": 1,
         "red_spheres_or_triplets": 1,
         "green_spheres_or_nions": 1,
         "gold_spheres": 1,
         "purple_spheres_or_triplets": 1,
     },
     "achievement_points": 20},

    # Использовать только любые 4 цвета
    {"id": "balanced_strategist", "name": "Уравновешенный Стратег",
     "description": "Использовать только 4 цвета сфер, триплетов или нионсов (один цвет не использовать вообще)",
     "condition": {"EXACTLY_4_COLORS": True}, "achievement_points": 40},

    # Только 3 цвета
    {"id": "minimalism_triumph", "name": "Триумф Минимализма",
     "description": "Использовать только 3 цвета сфер, триплетов или нионсов (два цвета не использовать вообще)",
     "condition": {"EXACTLY_3_COLORS": True}, "achievement_points": 50},

    # Только 2 цвета
    {"id": "duet_elements", "name": "Дуэт Стихий",
     "description": "Использовать только 2 цвета сфер, триплетов или нионсов (три цвета не использовать вообще)",
     "condition": {"EXACTLY_2_COLORS": True}, "achievement_points": 80},

    # Только 1 цвет
    {"id": "monochrome_genius", "name": "Монохромный Гений",
     "description": "Использовать только 1 цвет сфер, триплетов или нионсов (остальные 4 цвета не использовать вообще)",
     "condition": {"EXACTLY_1_COLOR": True}, "achievement_points": 100},

    # Количество собранных триплетов
    {"id": "triad_initiate", "name": "Триадный Инициат", "description": "Собрать суммарно 50 триплетов", "condition": {"total_triplets": 50}, "achievement_points": 10},
    {"id": "chain_reactor", "name": "Цепной Реактор", "description": "Собрать суммарно 100 триплетов", "condition": {"total_triplets": 100}, "achievement_points": 20},
    {"id": "combo_king", "name": "Король Комбинаций", "description": "Собрать суммарно 200 триплетов", "condition": {"total_triplets": 200}, "achievement_points": 50},

    # Специальные (фиолетовые)
    {"id": "darkness_gift", "name": "Скромный Дар Тьмы", "description": "5 раз получить минимальный бонус фиолетовых сфер", "condition": {"purple_min_bonus_times": 5}, "achievement_points": 60},
    {"id": "shine_apotheosis", "name": "Апофеоз Сияния", "description": "5 раз получить максимальный бонус фиолетовых сфер", "condition": {"purple_max_bonus_times": 5}, "achievement_points": 60},
]

# Звания по сумме очков достижений (не игровых!)
RANKS = [
    {"min_achievement_points": 0, "max_achievement_points": 100, "title": "Адепт объединения"},
    {"min_achievement_points": 101, "max_achievement_points": 400, "title": "Планетарный захватчик"},
    {"min_achievement_points": 401, "max_achievement_points": 600, "title": "Повелитель сфер"},
    {"min_achievement_points": 601, "max_achievement_points": 700, "title": "Опытный нексор"},
    {"min_achievement_points": 701, "max_achievement_points": 999, "title": "Наместник биндари"},
    {"min_achievement_points": 1000, "max_achievement_points": float("inf"), "title": "Император Лимнара"},
]
