const mini = window.MiniApp || {
  name: "web", ready() {}, expand() {}, haptic() {}, close() {}, popup() {}, openBot() {}, label() { return "Web Mini App"; },
};

const letters = "АВЕКМНОРСТУХ";

function generatePlate() {
  let plate = letters[Math.floor(Math.random() * letters.length)];
  plate += String(Math.floor(Math.random() * 1000)).padStart(3, "0");
  plate += letters[Math.floor(Math.random() * letters.length)];
  plate += letters[Math.floor(Math.random() * letters.length)];
  return plate;
}

function scorePlate(plate) {
  const digits = plate.slice(1, 4);
  const nums = [...digits].map(Number);
  if (nums[0] === nums[1] && nums[1] === nums[2]) return [100, "Три одинаковые цифры!"];
  if (nums[0] === nums[1] || nums[1] === nums[2]) return [20, "Две одинаковые цифры рядом"];
  if (plate[0] === plate[4]) return [50, "Зеркальные буквы"];
  return [15, "Обычный номерок"];
}

const plateEl = document.getElementById("plate");
const phraseEl = document.getElementById("phrase");
const pointsEl = document.getElementById("points");

document.getElementById("roll").addEventListener("click", () => {
  const plate = generatePlate();
  const [points, phrase] = scorePlate(plate);
  plateEl.textContent = plate;
  phraseEl.textContent = phrase;
  pointsEl.textContent = String(points);
  mini.haptic("medium");
});

document.getElementById("open-bot").addEventListener("click", () => {
  mini.openBot("https://t.me/Inspectorauto_bot", "https://max.ru/Inspectorauto_bot");
});
