const tg = window.Telegram?.WebApp;
tg?.ready();
tg?.expand();

const COLORS = [
  { id: "blue", label: "🔵", score: 10 },
  { id: "red", label: "🔴", score: 12 },
  { id: "green", label: "🟢", score: 15 },
  { id: "gold", label: "🟡", score: 25 },
  { id: "purple", label: "🟣", score: 18 },
];

const screens = {
  start: document.getElementById("screen-start"),
  choose: document.getElementById("screen-choose"),
  result: document.getElementById("screen-result"),
};

const ballsEl = document.getElementById("balls");
const roundLabel = document.getElementById("round-label");
const resultText = document.getElementById("result-text");
const resultDetail = document.getElementById("result-detail");
const scoreValue = document.getElementById("score-value");
const platformBadge = document.getElementById("platform-badge");

let round = 1;
let picks = [];

function show(name) {
  Object.values(screens).forEach((el) => el.classList.remove("active"));
  screens[name].classList.add("active");
}

function renderBalls() {
  ballsEl.innerHTML = "";
  COLORS.forEach((color, index) => {
    const btn = document.createElement("button");
    btn.className = `ball ${color.id}`;
    btn.textContent = color.label;
    btn.addEventListener("click", () => pick(color, index + 1));
    ballsEl.appendChild(btn);
  });
}

function pick(color, number) {
  picks.push(color);
  round += 1;
  if (round <= 5) {
    roundLabel.textContent = `Раунд ${round}`;
    tg?.HapticFeedback?.impactOccurred("light");
    return;
  }
  const score = picks.reduce((sum, item) => sum + item.score, 0) + (new Set(picks.map((p) => p.id)).size >= 4 ? 20 : 0);
  scoreValue.textContent = String(score);
  resultText.textContent = `Вы выбрали ${picks.map((p) => p.label).join(" ")}`;
  resultDetail.textContent = "Полная игра с триплетами и достижениями доступна в Telegram-боте.";
  show("result");
  tg?.showPopup?.({ title: "CB Balloons", message: `Счёт демо: ${score}` });
}

document.getElementById("btn-start").addEventListener("click", () => {
  round = 1;
  picks = [];
  roundLabel.textContent = "Раунд 1";
  renderBalls();
  show("choose");
});

document.getElementById("btn-again").addEventListener("click", () => show("start"));

document.getElementById("btn-bot").addEventListener("click", () => {
  if (tg?.openTelegramLink) {
    tg.openTelegramLink("https://t.me/");
  }
});

platformBadge.textContent = tg?.platform ? `Telegram Mini App · ${tg.platform}` : "Web Mini App";
