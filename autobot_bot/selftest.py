"""Локальная проверка Автобота: импорт модулей и работа calculate_plate."""
import os
import sys

os.environ["TELEGRAM_BOT_TOKEN"] = "test:dummy"
os.environ["TELEGRAM_POLLING_ENABLED"] = "false"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "bot"))

import autobot  # noqa: E402

print("imports: OK")

# Прогон по большому числу случайных номеров — не должно быть исключений
seen = set()
for _ in range(5000):
    plate = autobot.generate_plate()
    pts, phrase = autobot.calculate_plate(plate)
    assert isinstance(pts, int)
    assert isinstance(phrase, str) and phrase
    seen.add(phrase)
print(f"5000 random plates OK, unique phrases seen = {len(seen)}")

# Точечные проверки конкретных шаблонов
samples = [
    "А777АА", "К666ХХ", "С007КТ", "М911КТ", "О000ОО", "А123ВС",
    "Е321КХ", "Н555НН", "Т246ТР", "В864СР", "К550РС", "М314АМ",
    "А456МР", "Е374КХ", "Х404ЕМ", "Н726МК",
]
print("\nПримеры распознавания:")
for p in samples:
    pts, phrase = autobot.calculate_plate(p)
    print(f"  {p}: +{pts} — {phrase}")

print("\nALL AUTOBOT SELFTESTS PASSED")
