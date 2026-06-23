"""Локальная проверка CB Balloons без сети Telegram.

Прогоняет полную партию из 5 раундов и финальный подсчёт — это ровно тот путь,
где раньше бот «зависал» на кнопке «Принять» в 5-м раунде.
"""
import os
import sys
import tempfile

os.environ["TELEGRAM_BOT_TOKEN"] = "test:dummy"
os.environ["TELEGRAM_POLLING_ENABLED"] = "false"
DB = os.path.join(tempfile.gettempdir(), "cb_selftest.db")
if os.path.exists(DB):
    os.remove(DB)
os.environ["DB_FILE"] = DB

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "bot"))

# 1) Импорт всех модулей (ловит синтаксис/импорт-ошибки)
import application  # noqa: E402
import texts  # noqa: E402
from db.achievements import check_achievements, get_user_achievement_ids  # noqa: E402
from db.database import init_db, already_played_today, save_user, touch_last_play  # noqa: E402
from db.scores import get_player_stats, reset_chat, update_scores  # noqa: E402
from game.scoring import breakdown_collection, calculate_score  # noqa: E402
from game.session import start_session, get_session  # noqa: E402

print("imports: OK")

# 2) Проверяем, что build_application собирается (без запуска polling)
app = application.build_application()
assert app is not None
print("build_application: OK")

# 3) Симуляция полной партии 5 раундов через сессию
USER, CHAT = 111, 111
init_db()
save_user(USER, "tester")
session = start_session(USER, CHAT, private=True)
touch_last_play(USER, CHAT)

for r in range(1, 6):
    s = get_session(USER)
    # выбираем нужное число первых сфер
    for i in range(s.pick_count):
        s.toggle(i)
    assert s.selection_complete(), f"round {r}: selection not complete"
    s.commit_selection()
    if not s.is_last_round:
        s.advance_round()
print(f"5 rounds played, collection size = {len(get_session(USER).collection)}")

# 4) Финальный подсчёт + запись очков (тот самый падавший участок)
final = get_session(USER)
details, total = calculate_score(final.collection)
agg = breakdown_collection(final.collection)
update_scores(
    USER, "tester", CHAT, total,
    agg["triplets_total"], agg["nions_total"],
    agg["sphere_counts"], agg["triplet_counts"], agg["nions_counts"],
)
print(f"update_scores: OK (total={total})")

gc = {
    "blue_spheres": agg["sphere_counts"]["blue"], "red_spheres": agg["sphere_counts"]["red"],
    "green_spheres": agg["sphere_counts"]["green"], "gold_spheres": agg["sphere_counts"]["gold"],
    "purple_spheres": agg["sphere_counts"]["purple"], "blue_triplets": agg["triplet_counts"]["blue"],
    "red_triplets": agg["triplet_counts"]["red"], "green_triplets": agg["triplet_counts"]["green"],
    "purple_triplets": agg["triplet_counts"]["purple"], "green_nions": agg["nions_counts"]["green"],
}
new_ach = check_achievements(USER, CHAT, gc)
print(f"check_achievements: OK (new={new_ach})")

stats = get_player_stats(USER, CHAT)
assert stats and stats[0] == 1, stats
print(f"stats after game: games_played={stats[0]}, max_points={stats[1]}, ach_points={stats[5]}")
print(f"achievements unlocked: {get_user_achievement_ids(USER, CHAT)}")

# 5) Повторная партия — проверяем накопление и upsert
update_scores(USER, "tester", CHAT, 50, 1, 0,
              agg["sphere_counts"], agg["triplet_counts"], agg["nions_counts"])
stats2 = get_player_stats(USER, CHAT)
assert stats2[0] == 2, stats2
print(f"second game upsert: games_played={stats2[0]}")

reset_chat(CHAT)
assert get_player_stats(USER, CHAT) is None
print("reset_chat: OK")

print("\nALL SELFTESTS PASSED")
