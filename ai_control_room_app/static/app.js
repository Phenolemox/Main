// AI Control Room v0.3 — folder-based admin panel
const state = {
  summary: null,
  authed: false,
  configured: false,
  active: "server:metrics",
  pokerAdmin: null,
};

const $ = (id) => document.getElementById(id);
const esc = (v) => String(v ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

async function api(url, opts = {}) {
  const res = await fetch(url, { cache: "no-store", credentials: "same-origin", ...opts });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  if (!res.ok) {
    const msg = (data && (data.detail?.hint || data.detail || data.error)) || res.status;
    throw new Error(typeof msg === "string" ? msg : JSON.stringify(msg));
  }
  return data;
}

function toast(msg, kind = "") {
  const el = $("toast");
  el.textContent = msg;
  el.className = `toast ${kind}`;
  setTimeout(() => el.classList.add("hidden"), 3800);
}

// ---------- Navigation tree ----------
const TREE = [
  { id: "server", icon: "📁", name: "Сервер", items: [
    { id: "metrics", name: "Нагрузка и метрики" },
    { id: "services", name: "Службы" },
    { id: "ports", name: "Порты" },
    { id: "backups", name: "Бэкапы" },
  ]},
  { id: "github", icon: "📁", name: "GitHub", items: [
    { id: "repos", name: "Репозитории" },
    { id: "sync", name: "Статус синхронизации" },
  ]},
  { id: "bots", icon: "📁", name: "Боты", items: [
    { id: "poker-bot", name: "🃏 MyPoker" },
    { id: "cb-balloons-bot", name: "🎈 CB Balloons" },
    { id: "autobot-bot", name: "🚓 Autobot" },
  ]},
  { id: "local", icon: "📁", name: "Локальный ПК", items: [
    { id: "mirror", name: "Зеркало и пути" },
  ]},
  { id: "max", icon: "📁", name: "MAX Platform", items: [
    { id: "status", name: "Webhook и Mini App" },
  ]},
  { id: "tools", icon: "📁", name: "Безопасность и инструменты", items: [
    { id: "panels", name: "Панели" },
    { id: "actions", name: "Действия" },
  ]},
];

function renderTree() {
  const tree = $("tree");
  tree.innerHTML = "";
  const [folderId, sub] = state.active.split(":");
  for (const folder of TREE) {
    const open = folder.id === folderId;
    const div = document.createElement("div");
    div.className = `folder ${open ? "open" : ""}`;
    const badge = folderBadge(folder.id);
    div.innerHTML = `
      <div class="folder-head ${open ? "active" : ""}" data-folder="${folder.id}">
        <span class="chevron">▶</span>
        <span class="folder-icon">${folder.icon}</span>
        <span class="folder-name">${esc(folder.name)}</span>
        ${badge ? `<span class="folder-badge">${badge}</span>` : ""}
      </div>
      <div class="subitems">
        ${folder.items.map((it) => `
          <div class="subitem ${state.active === folder.id + ":" + it.id ? "active" : ""}" data-nav="${folder.id}:${it.id}">
            <span class="mini-dot"></span><span>${esc(it.name)}</span>
          </div>`).join("")}
      </div>`;
    tree.appendChild(div);
  }
  tree.querySelectorAll(".folder-head").forEach((el) => {
    el.addEventListener("click", () => {
      const fid = el.dataset.folder;
      const folder = TREE.find((f) => f.id === fid);
      navigate(`${fid}:${folder.items[0].id}`);
    });
  });
  tree.querySelectorAll(".subitem").forEach((el) => {
    el.addEventListener("click", () => navigate(el.dataset.nav));
  });
}

function folderBadge(id) {
  const s = state.summary;
  if (!s) return "";
  if (id === "bots") {
    const online = (s.bots || []).filter((b) => true).length;
    return `${(s.bots || []).length}`;
  }
  if (id === "server") {
    const cpu = s.metrics?.cpu_percent;
    return cpu != null ? `${cpu}%` : "";
  }
  if (id === "max") {
    return s.max ? `${s.max.configured_count}/${s.max.total}` : "";
  }
  return "";
}

function navigate(active) {
  state.active = active;
  renderTree();
  render();
}

// ---------- Gauges ----------
function gauge(value, label, sub) {
  const pct = Math.max(0, Math.min(100, value ?? 0));
  const r = 42, c = 2 * Math.PI * r;
  const off = c * (1 - pct / 100);
  const color = pct > 85 ? "var(--bad)" : pct > 65 ? "var(--warn)" : "var(--good)";
  return `
    <div class="gauge">
      <svg width="110" height="110" viewBox="0 0 110 110">
        <circle class="gauge-track" cx="55" cy="55" r="${r}" fill="none" stroke-width="9"></circle>
        <circle cx="55" cy="55" r="${r}" fill="none" stroke="${color}" stroke-width="9"
          stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${off}"></circle>
      </svg>
      <div style="margin-top:-72px" class="gauge-val">${value != null ? value + "%" : "—"}</div>
      <div style="margin-top:34px" class="gauge-label">${esc(label)}</div>
      <div class="gauge-sub">${esc(sub || "")}</div>
    </div>`;
}

// ---------- Views ----------
function render() {
  const [folder, sub] = state.active.split(":");
  const c = $("content");
  const s = state.summary;
  $("crumbs").textContent = crumbLabel(folder, sub);
  if (!s) { c.innerHTML = `<div class="loading">Загрузка панели…</div>`; return; }

  const views = {
    "server:metrics": viewMetrics,
    "server:services": viewServices,
    "server:ports": viewPorts,
    "server:backups": viewBackups,
    "github:repos": viewRepos,
    "github:sync": viewSync,
    "bots:poker-bot": () => viewBot("poker-bot"),
    "bots:cb-balloons-bot": () => viewBot("cb-balloons-bot"),
    "bots:autobot-bot": () => viewBot("autobot-bot"),
    "local:mirror": viewLocal,
    "max:status": viewMax,
    "tools:panels": viewPanels,
    "tools:actions": viewActions,
  };
  (views[state.active] || viewMetrics)(c);
}

function crumbLabel(folder, sub) {
  const f = TREE.find((x) => x.id === folder);
  if (!f) return "Control Room";
  const it = f.items.find((x) => x.id === sub);
  return `${f.name}${it ? " / " + it.name.replace(/^[^ ]+ /, "") : ""}`;
}

function viewMetrics(c) {
  const m = state.summary.metrics || {};
  const mem = m.memory || {}, disk = m.disk || {}, load = m.load || {};
  const up = m.uptime_seconds;
  const upStr = up ? `${Math.floor(up / 86400)}д ${Math.floor((up % 86400) / 3600)}ч` : "—";
  c.innerHTML = `
    <div class="card">
      <div class="card-head"><h3>Нагрузка сервера</h3><span class="svc-meta">${esc(state.summary.public_domain)} · ${esc(m.generated_at || "")}</span></div>
      <div class="gauges">
        ${gauge(m.cpu_percent, "CPU", `${load.cores || "?"} ядер`)}
        ${gauge(mem.percent, "RAM", `${mem.used_mb || 0} / ${mem.total_mb || 0} MB`)}
        ${gauge(disk.percent, "Диск", `${disk.used_gb || 0} / ${disk.total_gb || 0} GB`)}
        ${gauge(load.load1_percent, "LA (1м)", `${load.load1 ?? "—"} / ${load.load5 ?? "—"} / ${load.load15 ?? "—"}`)}
      </div>
    </div>
    <div class="spacer"></div>
    <div class="grid cols-2">
      <div class="card">
        <h3>Сводка</h3>
        <div class="kv"><span class="k">Uptime</span><span class="v">${upStr}</span></div>
        <div class="kv"><span class="k">Свободно RAM</span><span class="v">${mem.available_mb || 0} MB</span></div>
        <div class="kv"><span class="k">Свободно диска</span><span class="v">${disk.free_gb || 0} GB</span></div>
        <div class="kv"><span class="k">Версия панели</span><span class="v">${esc(state.summary.version)}</span></div>
      </div>
      <div class="card">
        <h3>Активные службы</h3>
        ${(state.summary.services || []).slice(0, 8).map((sv) => `
          <div class="kv"><span class="k">${esc(sv.name)}</span>
          <span class="pill ${sv.ok ? "good" : "bad"}">${esc(sv.active)}</span></div>`).join("")}
      </div>
    </div>`;
}

function viewServices(c) {
  const svcs = state.summary.services || [];
  c.innerHTML = `<div class="card"><h3>Управляемые службы (${svcs.length})</h3>
    ${svcs.map((sv) => `
      <div class="svc-row">
        <span class="dot ${sv.ok ? "good" : "bad"}"></span>
        <span class="name">${esc(sv.name)}</span>
        <span class="svc-meta">enabled: ${esc(sv.enabled)}</span>
        <span class="pill ${sv.ok ? "good" : "bad"}">${esc(sv.active)}</span>
      </div>`).join("")}
    <div class="spacer"></div>
    <button class="btn ghost sm" data-log="bots-hub">Логи bots-hub</button>
    <button class="btn ghost sm" data-log="ai-control-room">Логи control-room</button>
  </div><div class="spacer"></div><pre id="logBox" class="terminal small hidden"></pre>`;
  c.querySelectorAll("[data-log]").forEach((b) => b.addEventListener("click", () => loadLog(b.dataset.log)));
}

async function loadLog(svc) {
  const box = $("logBox");
  box.classList.remove("hidden");
  box.textContent = `Загрузка логов ${svc}…`;
  try {
    const r = await api(`/api/logs/${svc}?lines=120`);
    box.textContent = r.stdout || r.stderr || "(пусто)";
  } catch (e) { box.textContent = "Ошибка: " + e.message; }
}

function viewPorts(c) {
  c.innerHTML = `<div class="card"><h3>Прослушиваемые порты (10.8.0.1)</h3>
    <pre class="terminal">${esc((state.summary.ports || []).join("\n"))}</pre></div>`;
}

function viewBackups(c) {
  const b = state.summary.backups || [];
  c.innerHTML = `<div class="card"><h3>Последние бэкапы</h3>
    <table><tr><th>Путь</th><th>Размер</th><th>Время (UTC)</th></tr>
    ${b.map((x) => `<tr><td>${esc(x.path)}</td><td>${(x.size / 1024).toFixed(0)} KB</td><td>${esc(x.mtime)}</td></tr>`).join("")}
    </table>
    <div class="spacer"></div>
    <button class="btn" data-action="backup" ${state.authed ? "" : "disabled"}>Создать бэкап сейчас</button>
    <pre id="actOut" class="terminal small hidden"></pre></div>`;
  bindActions(c);
}

function viewRepos(c) {
  const gh = state.summary.github || {};
  c.innerHTML = `<div class="card">
    <div class="card-head"><h3>GitHub · Phenolemox</h3>
    <span class="pill ${gh.authenticated ? "good" : "bad"}">${gh.authenticated ? "authenticated" : "not authed"}</span></div>
    <table><tr><th>Репозиторий</th><th>Обновлён</th><th></th></tr>
    ${(gh.repos || []).map((r) => `<tr><td>${esc(r.name)}</td><td>${esc((r.updatedAt || "").slice(0,10))}</td>
      <td><a class="bot-links" href="${esc(r.url)}" target="_blank" rel="noopener" style="color:var(--accent)">открыть ↗</a></td></tr>`).join("")}
    </table></div>`;
}

function viewSync(c) {
  const projects = state.summary.projects || [];
  c.innerHTML = `<div class="card"><h3>Статус репозиториев на сервере</h3>
    ${projects.map((p) => {
      const rs = p.repo_state || {};
      return `<div class="svc-row">
        <span class="dot ${rs.ok ? (rs.dirty ? "warn" : "good") : "bad"}"></span>
        <span class="name">${esc(p.name)}</span>
        <span class="svc-meta">HEAD ${esc(rs.head || "?")} · origin ${esc(rs.origin_main || "?")} ${rs.dirty ? "· dirty" : ""}</span>
      </div>`;
    }).join("")}
    <div class="spacer"></div>
    <button class="btn" data-action="bots-platform-deploy" ${state.authed ? "" : "disabled"}>Деплой ботов из GitHub</button>
    <pre id="actOut" class="terminal small hidden"></pre></div>`;
  bindActions(c);
}

function viewBot(botId) {
  const c = $("content");
  const bot = (state.summary.bots || []).find((b) => b.id === botId);
  if (!bot) { c.innerHTML = `<div class="card">Бот не найден</div>`; return; }
  c.innerHTML = `
    <div class="card">
      <div class="bot-row" style="margin:0">
        <div class="bot-emoji">${esc(bot.emoji)}</div>
        <div class="bot-info">
          <div class="name">${esc(bot.name)} <span class="svc-meta">· ${esc(bot.service)}</span></div>
          <div class="bot-links">
            <a href="${esc(bot.public_miniapp)}" target="_blank" rel="noopener">Mini App (TG)</a>
            <a href="${esc(bot.public_miniapp)}?platform=max" target="_blank" rel="noopener">Mini App (MAX)</a>
            <a href="${esc(bot.telegram)}" target="_blank" rel="noopener">Telegram</a>
            <a href="${esc(bot.public)}/health" target="_blank" rel="noopener">Health</a>
          </div>
        </div>
        <div style="text-align:right">
          <span id="botState" class="pill warn">…</span>
          <div style="margin-top:8px"><label class="switch"><input type="checkbox" id="botToggle" ${state.authed ? "" : "disabled"}><span class="slider"></span></label></div>
        </div>
      </div>
      ${state.authed ? "" : `<div class="note">⚠ Войдите как админ, чтобы включать/выключать бота.</div>`}
    </div>
    <div class="spacer"></div>
    <div class="grid cols-2">
      <div class="card"><h3>Здоровье и состояние</h3><pre id="botHealth" class="terminal small">Загрузка…</pre></div>
      <div class="card">
        <div class="card-head"><h3>Логи</h3><button class="btn ghost sm" id="loadBotLog">Обновить</button></div>
        <pre id="botLog" class="terminal small">—</pre>
      </div>
    </div>
    ${botId === "poker-bot" ? pokerAdminBlock() : ""}`;

  loadBotState(botId);
  $("loadBotLog")?.addEventListener("click", () => loadBotLog(bot.service));
  loadBotLog(bot.service);
  const tog = $("botToggle");
  if (tog) tog.addEventListener("change", () => toggleBot(botId, tog.checked));
  if (botId === "poker-bot") bindPokerAdmin();
}

async function loadBotState(botId) {
  try {
    const r = await api("/api/bots");
    const bot = r.items.find((b) => b.id === botId);
    const active = bot?.service_state?.active === "active";
    const healthy = bot?.health?.ok;
    $("botState").className = `pill ${active ? "good" : "bad"}`;
    $("botState").textContent = active ? "running" : "stopped";
    const tog = $("botToggle");
    if (tog) tog.checked = active;
    $("botHealth").textContent = JSON.stringify(bot?.health?.body || bot?.health || {}, null, 2);
  } catch (e) { $("botHealth").textContent = "Ошибка: " + e.message; }
}

async function loadBotLog(svc) {
  const box = $("botLog");
  box.textContent = "Загрузка…";
  try { const r = await api(`/api/logs/${svc}?lines=80`); box.textContent = (r.stdout || r.stderr || "(пусто)").slice(-4000); }
  catch (e) { box.textContent = "Ошибка: " + e.message; }
}

async function toggleBot(botId, on) {
  const action = on ? "start" : "stop";
  try {
    await api(`/api/bots/${botId}/toggle`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action }),
    });
    toast(`Бот ${botId}: ${on ? "включён" : "выключен"}`, "good");
    setTimeout(() => loadBotState(botId), 1200);
  } catch (e) {
    toast("Не удалось переключить: " + e.message, "bad");
    loadBotState(botId);
  }
}

function viewLocal(c) {
  const l = state.summary.local || {};
  c.innerHTML = `<div class="card"><h3>Локальное зеркало и пути</h3>
    <div class="kv"><span class="k">Рабочая папка</span><span class="v">${esc(l.workspace)}</span></div>
    ${(l.mirror_paths || []).map((p) => `<div class="kv"><span class="k">Зеркало</span><span class="v">${esc(p)}</span></div>`).join("")}
    ${(l.repos || []).map((r) => `<div class="kv"><span class="k">Репозиторий</span><span class="v">${esc(r)}</span></div>`).join("")}
    <div class="note">${esc(l.note || "")}</div>
  </div>
  <div class="spacer"></div>
  <div class="grid cols-2">
    <div class="card"><h3>Main (сервер)</h3><pre class="terminal small">${esc(JSON.stringify(l.server_repo_main || {}, null, 2))}</pre></div>
    <div class="card"><h3>poker-bot (сервер)</h3><pre class="terminal small">${esc(JSON.stringify(l.server_repo_poker || {}, null, 2))}</pre></div>
  </div>`;
}

function viewMax(c) {
  const mx = state.summary.max || {};
  c.innerHTML = `<div class="card">
    <div class="card-head"><h3>MAX Platform</h3>
    <span class="pill ${mx.ready ? "good" : "warn"}">${mx.configured_count}/${mx.total} ботов готовы</span></div>
    <div class="note">${esc(mx.note || "")}</div>
    <div class="spacer"></div>
    ${(mx.bots || []).map((b) => `
      <div class="svc-row">
        <span class="bot-emoji">${esc(b.emoji)}</span>
        <div class="bot-info">
          <div class="name">${esc(b.name)}</div>
          <div class="bot-links">
            <a href="${esc(b.miniapp_url)}?platform=max" target="_blank" rel="noopener">MAX Mini App ↗</a>
            <span style="color:var(--muted);font-size:12px;padding:3px 0">webhook: ${esc(b.webhook_url)}</span>
          </div>
        </div>
        <span class="pill ${b.bot_token_configured ? "good" : "warn"}">${b.bot_token_configured ? "token ✓" : "нужен MAX_BOT_TOKEN"}</span>
      </div>`).join("")}
  </div>`;
}

function viewPanels(c) {
  const p = state.summary.panels || [];
  c.innerHTML = `<div class="card"><h3>Внутренние панели и инструменты</h3>
    <div class="links-wrap">
      ${p.map((x) => `<a class="link-tile" href="${esc(x.url)}" target="_blank" rel="noopener">
        <strong>${esc(x.name)}</strong><span class="lt-kind">${esc(x.kind)}</span></a>`).join("")}
      <a class="link-tile" href="https://bots.${esc(state.summary.public_domain)}" target="_blank" rel="noopener"><strong>Bots Hub</strong><span class="lt-kind">public</span></a>
    </div>
    <div class="note">Панели слушают внутренний интерфейс 10.8.0.1 (VPN). Откроются при подключении к VPN сервера.</div>
  </div>`;
}

function viewActions(c) {
  c.innerHTML = `<div class="card"><h3>Действия (требуется вход)</h3>
    <div class="actions-row">
      <button class="btn" data-action="backup">Бэкап</button>
      <button class="btn" data-action="telegram-set-commands">Telegram команды</button>
      <button class="btn" data-action="poker-reset-sessions">Сброс сессий покера</button>
      <button class="btn" data-action="poker-qa">Poker QA</button>
      <button class="btn" data-action="bots-platform-deploy">Деплой ботов</button>
    </div>
    <pre id="actOut" class="terminal small hidden"></pre>
    ${state.authed ? "" : `<div class="note">⚠ Войдите как админ для запуска действий.</div>`}
  </div>`;
  bindActions(c);
}

function bindActions(c) {
  c.querySelectorAll("[data-action]").forEach((b) => {
    b.addEventListener("click", async () => {
      const out = $("actOut");
      if (out) { out.classList.remove("hidden"); out.textContent = `Запуск ${b.dataset.action}…`; }
      try {
        const r = await api(`/api/actions/${b.dataset.action}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
        if (out) out.textContent = (r.stdout || r.stderr || JSON.stringify(r)).slice(-4000);
        toast("Готово: " + b.dataset.action, "good");
      } catch (e) { if (out) out.textContent = "Ошибка: " + e.message; toast("Ошибка: " + e.message, "bad"); }
    });
  });
}

// ---------- Poker admin (preserved) ----------
function pokerAdminBlock() {
  return `<div class="spacer"></div>
  <div class="card">
    <div class="card-head"><h3>Poker Admin</h3><button class="btn ghost sm" id="loadPoker" ${state.authed ? "" : "disabled"}>Загрузить данные</button></div>
    <div id="pokerSummary" class="grid cols-4"></div>
    <div class="spacer"></div>
    <div class="grid cols-2">
      <div>
        <h3 style="font-size:14px">Score Adjust</h3>
        <div class="form-grid">
          <input id="scoreUserId" type="number" placeholder="User ID">
          <input id="scoreDelta" type="number" placeholder="Delta">
          <input id="scoreReason" placeholder="Причина" value="control_room_adjust">
          <button class="btn sm" id="adjustScore">Применить</button>
        </div>
      </div>
      <div>
        <h3 style="font-size:14px">Attempts Grant</h3>
        <div class="form-grid">
          <input id="grantUserId" type="number" placeholder="User ID">
          <input id="grantAmount" type="number" value="1" placeholder="Кол-во">
          <button class="btn sm" id="grantAttempts">Выдать</button>
        </div>
      </div>
    </div>
    <pre id="pokerOut" class="terminal small hidden"></pre>
  </div>`;
}

function bindPokerAdmin() {
  $("loadPoker")?.addEventListener("click", async () => {
    const sumEl = $("pokerSummary");
    sumEl.innerHTML = `<div class="loading">Загрузка…</div>`;
    try {
      const r = await api("/api/poker-admin");
      state.pokerAdmin = r;
      const s = r.summary || {};
      sumEl.innerHTML = Object.entries(s).slice(0, 8).map(([k, v]) =>
        `<div class="card" style="padding:12px"><div class="gauge-sub">${esc(k)}</div><div style="font-size:20px;font-weight:800">${esc(typeof v === "object" ? JSON.stringify(v) : v)}</div></div>`).join("") || `<div class="note">Нет сводки</div>`;
    } catch (e) { sumEl.innerHTML = `<div class="note">Ошибка: ${esc(e.message)}</div>`; }
  });
  $("adjustScore")?.addEventListener("click", async () => {
    try {
      await api("/api/poker-admin/score-adjust", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: +$("scoreUserId").value, delta: +$("scoreDelta").value, scope: "global", reason: $("scoreReason").value }) });
      toast("Score обновлён", "good");
    } catch (e) { toast("Ошибка: " + e.message, "bad"); }
  });
  $("grantAttempts")?.addEventListener("click", async () => {
    try {
      await api("/api/poker-admin/attempts-grant", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: +$("grantUserId").value, amount: +$("grantAmount").value, scope: "private", reason: "control_room_attempt_grant" }) });
      toast("Попытки выданы", "good");
    } catch (e) { toast("Ошибка: " + e.message, "bad"); }
  });
}

// ---------- Auth ----------
async function refreshAuth() {
  try {
    const me = await api("/api/auth/me");
    state.authed = !!me.authenticated;
    state.configured = !!me.configured;
  } catch { state.authed = false; }
  updateAuthUI();
}

function updateAuthUI() {
  const pill = $("authState"), dot = $("authDot"), label = $("authLabel");
  if (state.authed) {
    pill.className = "pill good"; pill.textContent = "admin";
    dot.className = "dot good"; label.textContent = "Авторизован";
    $("login").classList.add("hidden"); $("loginPassword").classList.add("hidden"); $("logout").classList.remove("hidden");
  } else {
    pill.className = "pill warn"; pill.textContent = state.configured ? "гость" : "no token";
    dot.className = "dot warn"; label.textContent = "Гость (только чтение)";
    $("login").classList.remove("hidden"); $("loginPassword").classList.remove("hidden"); $("logout").classList.add("hidden");
  }
}

async function login() {
  const pw = $("loginPassword").value;
  if (!pw) return;
  try {
    await api("/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ password: pw }) });
    $("loginPassword").value = "";
    await refreshAuth();
    toast("Вход выполнен", "good");
    render();
  } catch (e) { toast("Ошибка входа: " + e.message, "bad"); }
}

async function logout() {
  try { await api("/api/auth/logout", { method: "POST" }); } catch {}
  await refreshAuth();
  render();
}

async function loadSummary() {
  try {
    state.summary = await api("/api/summary");
    renderTree();
    render();
  } catch (e) {
    $("content").innerHTML = `<div class="card"><h3>Ошибка загрузки</h3><div class="note">${esc(e.message)}</div></div>`;
  }
}

// ---------- Init ----------
$("login").addEventListener("click", login);
$("logout").addEventListener("click", logout);
$("refresh").addEventListener("click", () => { loadSummary(); refreshAuth(); });
$("loginPassword").addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });
$("menuToggle").addEventListener("click", () => $("sidebar").classList.toggle("open"));

renderTree();
refreshAuth().then(loadSummary);
setInterval(() => { if (state.active === "server:metrics") loadSummary(); }, 30000);
