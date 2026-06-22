const S = { user: null, data: null };
const $ = (q) => document.querySelector(q);
const $$ = (q) => Array.from(document.querySelectorAll(q));
const esc = (v) => String(v ?? "").replace(/[&<>\"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]));
const money = (v) => `${Number(v || 0).toLocaleString("ru-RU")} PCF`;

async function post(url, data = {}) {
  const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload.detail || "API error");
  return payload;
}

async function get(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload.detail || "API error");
  return payload;
}

function toast(message) {
  const node = $("#toast");
  node.textContent = message;
  node.classList.remove("hidden");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => node.classList.add("hidden"), 2800);
}

function header() {
  $("#currentUser").textContent = S.user ? `${S.user.username} // ${S.user.role}` : "offline";
  $("#balance").textContent = S.user ? money(S.user.balance) : "0 PCF";
  $("#adminTab").style.display = S.user && S.user.role === "admin" ? "" : "none";
}

async function login(username, password) {
  const data = await post("/api/login", { username, password });
  S.user = data.user;
  localStorage.setItem("pcf_user_id", S.user.id);
  toast(`Вход: ${S.user.username}`);
  await loadState();
}

async function loadState() {
  const id = S.user?.id || localStorage.getItem("pcf_user_id") || 2;
  const data = await get(`/api/state?user_id=${id}`);
  S.data = data;
  if (data.user) S.user = data.user;
  render();
}

function stat(label, value) { return `<span class="stat">${label}<br><b>${value}</b></span>`; }
function badge(value) { return `<span class="badge">${esc(value)}</span>`; }

function fighterCard(f, actions = "") {
  return `<article class="card"><div class="eyebrow">${esc(f.rarity)} // ${esc(f.owner_status)}</div><h3>${esc(f.name)}</h3><p class="meta">${esc(f.nickname)}</p><p>${esc(f.description)}</p><div class="badges">${badge(f.race)}${badge(f.creature_type)}${badge(f.contract)}${badge(f.status)}</div><div class="statline">${stat("POW",f.physical_power)}${stat("MAG",f.magic)}${stat("SPD",f.speed)}${stat("INT",f.intelligence)}${stat("MED",f.media)}</div><p class="meta">PCF ${f.pcf_wins}-${f.pcf_losses}</p><div class="actions">${actions}</div></article>`;
}

function fightCard(event, fight) {
  const canBet = S.user && S.user.role !== "admin" && event.status === "bets_open" && fight.status === "open";
  return `<div class="fight"><div class="fighters-row"><div>${esc(fight.fighter_a_name)}<br><span class="meta">x${fight.odds_a}</span></div><div class="vs">VS</div><div>${esc(fight.fighter_b_name)}<br><span class="meta">x${fight.odds_b}</span></div></div><div class="badges">${badge(fight.fight_type)}${badge(fight.status)}${fight.winner_fighter_id ? badge("winner #" + fight.winner_fighter_id) : ""}</div>${canBet ? `<div class="actions"><button onclick="bet(${event.id},${fight.id},${fight.fighter_a_id})">Ставка A</button><button onclick="bet(${event.id},${fight.id},${fight.fighter_b_id})">Ставка B</button></div>` : ""}</div>`;
}

function renderEvents() {
  const events = S.data?.events || [];
  $("#eventsList").innerHTML = events.length ? events.map(e => `<article class="card"><div class="eyebrow">${esc(e.status)} // ${esc(e.event_type)}</div><h3>${esc(e.title)}</h3><p class="meta">${esc(e.description || "Без описания")}</p><div class="badges">${badge("random " + e.random_factor)}${badge("skills " + e.skill_factor)}</div>${(e.fights || []).map(f => fightCard(e,f)).join("")}${S.user?.role === "admin" && e.status !== "completed" ? `<div class="actions"><button class="primary" onclick="calcEvent(${e.id})">Рассчитать</button></div>` : ""}</article>`).join("") : `<div class="card"><h3>Нет событий</h3><p class="meta">Создай первое событие в админке.</p></div>`;
}

function renderMarket() {
  const market = S.data?.market || [];
  $("#marketList").innerHTML = market.length ? market.map(f => fighterCard(f, `<button class="primary" onclick="buy(${f.id})">Купить ${money(f.price)}</button><button onclick="claim(${f.id})">Первый боец</button>`)).join("") : `<div class="card"><h3>Рынок пуст</h3></div>`;
}

function renderStable() {
  const fighters = S.data?.my_fighters || [];
  const actions = (id) => ["physical_power","magic","speed","intelligence","media"].map(s => `<button onclick="train(${id},'${s}')">+ ${s}</button>`).join("");
  $("#myFightersList").innerHTML = fighters.length ? fighters.map(f => fighterCard(f, actions(f.id))).join("") : `<div class="card"><h3>Конюшня пустая</h3><p class="meta">Сделай ставку и забери первого бойца.</p></div>`;
}

function renderTraining() {
  const sessions = S.data?.training_sessions || [];
  $("#trainingList").innerHTML = sessions.length ? sessions.map(t => `<article class="card"><div class="eyebrow">${esc(t.status)}</div><h3>${esc(t.fighter_name)}</h3><p class="meta">${esc(t.stat)} до ${esc(t.finish_at)}</p>${t.status === "active" ? `<button class="primary" onclick="finishTraining(${t.id})">Забрать результат</button>` : `<p class="meta">${esc(t.result_json)}</p>`}</article>`).join("") : `<div class="card"><h3>Нет тренировок</h3></div>`;
}

function renderAdmin() {
  $("#adminSummary").innerHTML = S.user?.role === "admin" ? `<div class="card"><h3>Ядро активно</h3><p class="meta">Форма события отправляет POST /api/event. Кнопка больше не мёртвая.</p></div>` : `<div class="card"><h3>Нет доступа</h3></div>`;
}

function render() { header(); renderEvents(); renderMarket(); renderStable(); renderTraining(); renderAdmin(); }

window.bet = async (event_id, fight_id, chosen_fighter_id) => { try { const amount = Number(prompt("Сумма ставки", "100")); if (!amount) return; await post("/api/bet", { user_id: S.user.id, event_id, fight_id, chosen_fighter_id, amount }); toast("Ставка принята"); await loadState(); } catch (e) { toast(e.message); } };
window.buy = async (fighter_id) => { try { await post("/api/market-buy", { user_id: S.user.id, fighter_id }); toast("Боец куплен"); await loadState(); } catch (e) { toast(e.message); } };
window.claim = async (fighter_id) => { try { await post("/api/claim-first-fighter", { user_id: S.user.id, fighter_id, contract: "standard" }); toast("Первый боец закреплён"); await loadState(); } catch (e) { toast(e.message); } };
window.train = async (fighter_id, stat) => { try { await post("/api/train", { user_id: S.user.id, fighter_id, stat }); toast("Тренировка запущена"); await loadState(); } catch (e) { toast(e.message); } };
window.finishTraining = async (id) => { try { await post(`/api/finish-training/${id}?user_id=${S.user.id}`, {}); toast("Тренировка завершена"); await loadState(); } catch (e) { toast(e.message); } };
window.calcEvent = async (event_id) => { try { await post("/api/calc-event", { event_id }); toast("Событие рассчитано"); await loadState(); } catch (e) { toast(e.message); } };

function bind() {
  $("#loginBtn").onclick = () => login($("#loginUsername").value, $("#loginPassword").value);
  $("#loginPlayerBtn").onclick = () => login("player", "player");
  $("#loginAdminBtn").onclick = () => login("admin", "admin");
  $("#refreshBtn").onclick = loadState;
  $$(".tabs button").forEach(btn => btn.onclick = () => { $$(".tabs button").forEach(b => b.classList.toggle("active", b === btn)); $$(".screen").forEach(s => s.classList.remove("active")); $("#screen-" + btn.dataset.tab).classList.add("active"); });
  $("#openEventModalBtn").onclick = () => $("#eventModal").classList.remove("hidden");
  $("#closeEventModalBtn").onclick = $("#cancelEventBtn").onclick = () => $("#eventModal").classList.add("hidden");
  $("#eventForm").onsubmit = async (ev) => { ev.preventDefault(); try { await post("/api/event", { name: $("#eventName").value, description: $("#eventDesc").value, status: $("#eventStatus").value, event_type: $("#eventType").value, published_on_home: true }); $("#eventModal").classList.add("hidden"); toast("Событие создано"); await loadState(); } catch (e) { toast(e.message); } };
}

function canvas() {
  const c = $("#arenaCanvas"), ctx = c.getContext("2d");
  function resize(){ c.width = innerWidth * devicePixelRatio; c.height = innerHeight * devicePixelRatio; }
  function draw(){ ctx.clearRect(0,0,c.width,c.height); const g = ctx.createRadialGradient(c.width*.5,c.height*.18,0,c.width*.5,c.height*.18,c.width*.8); g.addColorStop(0,"rgba(155,77,255,.22)"); g.addColorStop(.55,"rgba(255,91,26,.08)"); g.addColorStop(1,"rgba(0,0,0,0)"); ctx.fillStyle=g; ctx.fillRect(0,0,c.width,c.height); ctx.strokeStyle="rgba(155,77,255,.16)"; for(let y=c.height*.62;y<c.height;y+=42*devicePixelRatio){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(c.width,y);ctx.stroke()} requestAnimationFrame(draw); }
  addEventListener("resize", resize); resize(); draw();
}

bind(); canvas(); loadState().catch(e => toast(e.message));
