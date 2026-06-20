from app.game.cards import best_of_seven, evaluate_five
from app.game.scoring import score_duel


def test_royal_flush():
    result = evaluate_five(["♠10", "♠J", "♠Q", "♠K", "♠A"])
    assert result.name == "Роял-флеш"
    assert result.points == 150


def test_wheel_straight():
    result = evaluate_five(["♠A", "♥2", "♦3", "♣4", "♠5"])
    assert result.name == "Стрит"
    assert result.tiebreaker == (5,)


def test_best_of_seven_pair_vs_high():
    result = best_of_seven(["♠2", "♥5", "♦9", "♣K", "♠A"], ["♥A", "♦3"])
    assert result.name == "Пара"


def test_duel_scoring_by_category_diff():
    a = evaluate_five(["♠10", "♠J", "♠Q", "♠K", "♠A"])
    b = evaluate_five(["♠2", "♥2", "♦7", "♣9", "♠K"])
    score = score_duel("a", a, "b", b)
    assert score.winner == "a"
    assert score.delta_a == 30
    assert score.delta_b == -15
