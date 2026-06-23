const $ = (id) => document.getElementById(id);
let auth = {configured: false, authenticated: false};

function pill(ok, text) {
  const cls = ok === true ? "good" : ok === false ? "bad" : "warn";
  return `<span class="pill ${cls}">${text}</span>`;
}

function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function bytes(value) {
  const units = ["B", "KB", "MB", "GB"];
  let n = Number(value || 0);
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i += 1;
  }
  return `${n.toFixed(i ? 1 : 0)} ${units[i]}`;
}

function tokenHeaders(json = false) {
  const headers = {};
  if (json) headers["Content-Type"] = "application/json";
  return headers;
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {credentials: "same-origin", ...options});
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch (_err) {
    body = text;
  }
  if (!res.ok) {
    const detail = typeof body === "object" ? JSON.stringify(body, null, 2) : body;
    throw new Error(`${res.status} ${detail}`);
  }
  return body;
}

function updateAuthUi() {
  const state = $("authState");
  state.className = `pill ${auth.configured ? (auth.authenticated ? "good" : "bad") : "bad"}`;
  state.textContent = auth.configured ? (auth.authenticated ? "session ready" : "login required") : "token missing";
  $("loginPassword").classList.toggle("hidden", auth.authenticated || !auth.configured);
  $("login").classList.toggle("hidden", auth.authenticated || !auth.configured);
  $("logout").classList.toggle("hidden", !auth.authenticated);
}

async function loadAuth() {
  auth = await fetchJson("/api/auth/me");
  updateAuthUi();
}

async function login() {
  const password = $("loginPassword").value.trim();
  if (!password) {
    $("actionOutput").textContent = "Enter the control password.";
    return;
  }
  const result = await fetchJson("/api/auth/login", {
    method: "POST",
    headers: tokenHeaders(true),
    body: JSON.stringify({password}),
  });
  $("loginPassword").value = "";
  await loadAuth();
  $("actionOutput").textContent = `Logged in. Session TTL: ${Math.round((result.session_ttl_seconds || 0) / 3600)}h.`;
}

async function logout() {
  await fetchJson("/api/auth/logout", {
    method: "POST",
    headers: tokenHeaders(),
  });
  auth = {configured: auth.configured, authenticated: false};
  updateAuthUi();
  $("pokerAdminOutput").textContent = "Logged out.";
}

async function loadSummary() {
  const data = await fetchJson("/api/summary");
  render(data);
}

function render(data) {
  $("generatedAt").textContent = data.generated_at;
  $("actionState").innerHTML = data.write_actions_configured
    ? pill(auth.authenticated, auth.authenticated ? "session ready" : "login required")
    : pill(false, "token not configured");
  $("pokerAdminState").innerHTML = data.poker_admin_configured
    ? pill(auth.authenticated, auth.authenticated ? "poker admin ready" : "login required")
    : pill(false, "poker token missing");

  const healthOk = data.health.filter((h) => h.result.ok).length;
  const servicesOk = data.services.filter((s) => s.ok).length;
  const dirtyProjects = data.projects.filter((p) => p.repo_state?.dirty || p.app_state?.dirty).length;
  const newestBackup = data.backups[0]?.mtime || "missing";

  $("statusStrip").innerHTML = [
    metric("Health", `${healthOk}/${data.health.length}`, healthOk === data.health.length),
    metric("Services", `${servicesOk}/${data.services.length}`, servicesOk === data.services.length),
    metric("Git dirty", String(dirtyProjects), dirtyProjects === 0),
    metric("Newest backup", newestBackup, Boolean(data.backups.length)),
  ].join("");

  $("serverState").textContent = [
    ...data.server.disk,
    "",
    ...data.server.memory,
    "",
    data.server.uptime,
  ].join("\n");

  $("serviceCount").textContent = `${data.services.length} tracked`;
  $("services").innerHTML = data.services.map((s) => `
    <div class="card">
      <div>${esc(s.name)}</div>
      <div>${pill(s.ok, esc(s.active || "unknown"))}</div>
      <p class="muted">enabled: ${esc(s.enabled || "unknown")}</p>
    </div>
  `).join("");

  $("projects").innerHTML = data.projects.map((p) => `
    <div class="row">
      <strong>${esc(p.name)}</strong>
      <p class="muted">${esc(p.repo)}</p>
      ${gitLine("repo", p.repo_state)}
      ${gitLine("app", p.app_state)}
    </div>
  `).join("");

  const gh = data.github || {};
  $("githubState").innerHTML = pill(gh.ok, gh.ok ? "gh connected" : "gh offline");
  $("githubRepos").innerHTML = (gh.repos || []).map((repo) => `
    <div class="row">
      <strong>${esc(repo.name)}</strong>
      <p class="muted">${esc(repo.updatedAt || "")}</p>
      <a href="${esc(repo.url)}" target="_blank" rel="noreferrer">${esc(repo.url)}</a>
    </div>
  `).join("") || `<p class="muted">GitHub repos unavailable</p>`;

  $("poker").innerHTML = data.health
    .filter((h) => h.name.startsWith("poker"))
    .map((h) => `
      <div class="row">
        <strong>${esc(h.name)}</strong>
        <p>${pill(h.result.ok, h.result.ok ? "ok" : "error")} <span class="muted">${h.result.latency_ms || 0} ms</span></p>
        <pre class="terminal">${esc(JSON.stringify(h.result.body ?? h.result.error, null, 2))}</pre>
      </div>
    `).join("");

  const bots = data.bots || [];
  $("botCount").textContent = `${bots.length} registered`;
  $("bots").innerHTML = bots.map((bot) => `
    <div class="card">
      <div>${esc(bot.emoji || "🤖")} ${esc(bot.name)}</div>
      <p class="muted">${esc(bot.repo)}</p>
      <p>${pill(bot.admin_api_configured, bot.admin_api_configured ? "admin connected" : "admin token missing")}</p>
      <p class="muted">${esc(bot.api)}</p>
      <div class="bot-links">
        ${bot.miniapp ? `<a href="${esc(bot.miniapp)}" target="_blank" rel="noreferrer">Mini App</a>` : ""}
        ${bot.telegram ? `<a href="${esc(bot.telegram)}" target="_blank" rel="noreferrer">Telegram</a>` : ""}
        <a href="#" data-load-bot-admin="${esc(bot.id)}">Admin</a>
      </div>
    </div>
  `).join("");

  $("allBotsHealth").innerHTML = data.health.map((h) => `
    <div class="row">
      <strong>${esc(h.name)}</strong>
      <p>${pill(h.result.ok, h.result.ok ? "ok" : "error")} <span class="muted">${h.result.latency_ms || 0} ms</span></p>
    </div>
  `).join("");

  document.querySelectorAll("[data-load-bot-admin]").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      loadGenericBotAdmin(link.dataset.loadBotAdmin).catch((err) => {
        $("pokerAdminOutput").textContent = String(err);
      });
    });
  });

  $("panels").innerHTML = data.panels.map((p) => `
    <a href="${esc(p.url)}" target="_blank" rel="noreferrer">
      <strong>${esc(p.name)}</strong>
      <div class="muted">${esc(p.kind)} - ${esc(p.url)}</div>
    </a>
  `).join("");

  $("backups").innerHTML = data.backups.map((b) => `
    <div class="row">
      <strong>${esc(b.mtime)}</strong>
      <p class="muted">${esc(b.path)}</p>
      <span class="pill">${bytes(b.size)}</span>
    </div>
  `).join("");

  $("ports").textContent = data.ports.join("\n");
}

function metric(name, value, ok) {
  return `<div class="metric"><span class="muted">${esc(name)}</span><strong>${esc(value)}</strong>${pill(ok, ok ? "ok" : "check")}</div>`;
}

function gitLine(label, state) {
  if (!state) return "";
  if (!state.ok) return `<p>${label}: ${pill(false, esc(state.error || "not ok"))}</p>`;
  const synced = state.head && state.head === state.origin_main && !state.dirty;
  return `<p>${label}: ${pill(synced, synced ? "synced" : "check")} <span class="muted">${esc(state.head)} / ${esc(state.origin_main)}</span></p>`;
}

async function runAction(action) {
  $("actionOutput").textContent = `Running ${action}...`;
  const result = await fetchJson(`/api/actions/${action}`, {
    method: "POST",
    headers: tokenHeaders(),
  });
  $("actionOutput").textContent = JSON.stringify(result, null, 2);
  await loadSummary();
}

function settingId(key) {
  return `setting-${key.replace(/[^a-z0-9_-]/gi, "-")}`;
}

async function loadGenericBotAdmin(botId) {
  if (botId === "poker-bot") {
    return loadPokerAdmin();
  }
  $("pokerAdminOutput").textContent = `Loading ${botId} admin...`;
  const data = await fetchJson(`/api/bots/${encodeURIComponent(botId)}/admin`, {headers: tokenHeaders()});
  $("pokerAdminOutput").textContent = JSON.stringify(data, null, 2);
}

async function loadPokerAdmin() {
  $("pokerAdminOutput").textContent = "Loading poker admin...";
  const data = await fetchJson("/api/poker-admin", {headers: tokenHeaders()});
  renderPokerAdmin(data);
  $("pokerAdminOutput").textContent = "Poker admin loaded.";
}

function renderPokerAdmin(data) {
  const summary = data.summary || {};
  $("pokerAdminSummary").innerHTML = [
    metric("Users", summary.users ?? 0, true),
    metric("Chats", summary.chats ?? 0, true),
    metric("Scores", summary.score_entries ?? 0, true),
    metric("Attempts", summary.attempt_entries ?? 0, true),
    metric("Sessions", sessionCount(data.sessions), true),
  ].join("");

  const users = data.users?.items || [];
  $("pokerUsers").innerHTML = `
    <thead><tr><th>ID</th><th>User</th><th>Scores</th><th>Attempts</th><th>Status</th><th></th></tr></thead>
    <tbody>
      ${users.map((u) => `
        <tr>
          <td>${esc(u.id)}</td>
          <td><strong>${esc(u.display_name || u.username || "user")}</strong><div class="muted">@${esc(u.username || "-")}</div></td>
          <td>G ${esc(u.scores?.global || 0)} / D ${esc(u.scores?.duel || 0)} / C ${esc(u.scores?.chat || 0)}</td>
          <td>${esc(u.attempts_today?.used || 0)} / ${esc(u.attempts_today?.limit || 0)} <div class="muted">+${esc(u.attempts_today?.granted || 0)} granted</div></td>
          <td>${pill(!u.is_blocked, u.is_blocked ? "blocked" : "active")}</td>
          <td><button data-block-user="${esc(u.id)}" data-block-state="${u.is_blocked ? "false" : "true"}">${u.is_blocked ? "Unblock" : "Block"}</button></td>
        </tr>
      `).join("")}
    </tbody>
  `;

  const attempts = data.attempts?.items || [];
  $("pokerAttempts").innerHTML = `
    <thead><tr><th>Day</th><th>User</th><th>Scope</th><th>Used</th><th>Remaining</th><th>Chat</th></tr></thead>
    <tbody>
      ${attempts.length ? attempts.map((item) => `
        <tr>
          <td>${esc(item.day)}</td>
          <td><strong>#${esc(item.user_id)}</strong><div class="muted">${esc(item.display_name || item.username || "user")}</div></td>
          <td>${esc(item.scope)}</td>
          <td>${esc(item.used)} / ${esc(item.limit)} <div class="muted">+${esc(item.granted)} granted</div></td>
          <td>${esc(item.remaining)}</td>
          <td>${item.chat_id ? `#${esc(item.chat_id)} <div class="muted">${esc(item.chat_title || "")}</div>` : `<span class="muted">private</span>`}</td>
        </tr>
      `).join("") : `<tr><td colspan="6" class="muted">No attempts for ${esc(data.attempts?.day || "today")}.</td></tr>`}
    </tbody>
  `;

  const boards = data.leaderboards || {};
  $("pokerLeaderboards").innerHTML = ["global", "duel"].map((scope) => {
    const items = boards[scope] || [];
    return `
      <div class="row">
        <strong>${esc(scope)}</strong>
        ${items.length ? items.map((item) => `
          <p><span class="muted">#${esc(item.user_id)}</span> ${esc(item.display_name || item.username || "user")} - ${esc(item.score)}</p>
        `).join("") : `<p class="muted">empty</p>`}
      </div>
    `;
  }).join("");

  $("pokerSettings").innerHTML = (data.settings?.items || []).map((setting) => {
    const id = settingId(setting.key);
    return `
      <div class="row">
        <strong>${esc(setting.key)}</strong>
        <textarea id="${esc(id)}" spellcheck="false">${esc(JSON.stringify(setting.value, null, 2))}</textarea>
        <button data-save-setting="${esc(setting.key)}">Save setting</button>
      </div>
    `;
  }).join("");

  $("pokerAudit").innerHTML = (data.audit?.items || []).map((item) => `
    <div class="row">
      <strong>${esc(item.action)}</strong>
      <p class="muted">${esc(item.created_at)} / ${esc(item.actor)} / ${esc(item.target || "-")}</p>
      <pre class="terminal">${esc(JSON.stringify(item.meta || {}, null, 2))}</pre>
    </div>
  `).join("");

  document.querySelectorAll("[data-save-setting]").forEach((button) => {
    button.addEventListener("click", () => saveSetting(button.dataset.saveSetting));
  });
  document.querySelectorAll("[data-block-user]").forEach((button) => {
    button.addEventListener("click", () => toggleBlock(button.dataset.blockUser, button.dataset.blockState === "true"));
  });
}

function sessionCount(data) {
  const sessions = data?.body?.sessions || data?.sessions || {};
  const redis = sessions.redis || {};
  return Number(redis.classic || 0) + Number(redis.pending || 0) + Number(redis.duel || 0);
}

async function submitScoreAdjust() {
  const payload = {
    user_id: Number($("scoreUserId").value),
    delta: Number($("scoreDelta").value),
    scope: $("scoreScope").value,
    reason: $("scoreReason").value || "control_room_adjust",
  };
  if ($("scoreChatId").value) payload.chat_id = Number($("scoreChatId").value);
  const result = await fetchJson("/api/poker-admin/score-adjust", {
    method: "POST",
    headers: tokenHeaders(true),
    body: JSON.stringify(payload),
  });
  $("pokerAdminOutput").textContent = JSON.stringify(result, null, 2);
  await loadPokerAdmin();
}

async function submitScoreReset() {
  if (!confirm("Reset selected poker score ledger entries?")) return;
  const payload = {
    reason: $("resetReason").value || "control_room_reset",
  };
  if ($("resetScope").value) payload.scope = $("resetScope").value;
  if ($("resetUserId").value) payload.user_id = Number($("resetUserId").value);
  if ($("resetChatId").value) payload.chat_id = Number($("resetChatId").value);
  const result = await fetchJson("/api/poker-admin/score-reset", {
    method: "POST",
    headers: tokenHeaders(true),
    body: JSON.stringify(payload),
  });
  $("pokerAdminOutput").textContent = JSON.stringify(result, null, 2);
  await loadPokerAdmin();
}

async function submitAttemptsGrant() {
  const payload = {
    user_id: Number($("attemptGrantUserId").value),
    amount: Number($("attemptGrantAmount").value || 1),
    scope: $("attemptGrantScope").value,
    reason: $("attemptGrantReason").value || "control_room_attempt_grant",
  };
  if ($("attemptGrantChatId").value) payload.chat_id = Number($("attemptGrantChatId").value);
  if ($("attemptGrantDay").value) payload.day = $("attemptGrantDay").value.trim();
  const result = await fetchJson("/api/poker-admin/attempts-grant", {
    method: "POST",
    headers: tokenHeaders(true),
    body: JSON.stringify(payload),
  });
  $("pokerAdminOutput").textContent = JSON.stringify(result, null, 2);
  await loadPokerAdmin();
}

async function submitAttemptsReset() {
  if (!confirm("Reset selected poker attempt ledger entries for the selected day?")) return;
  const payload = {
    reason: $("attemptResetReason").value || "control_room_attempt_reset",
  };
  if ($("attemptResetScope").value) payload.scope = $("attemptResetScope").value;
  if ($("attemptResetUserId").value) payload.user_id = Number($("attemptResetUserId").value);
  if ($("attemptResetChatId").value) payload.chat_id = Number($("attemptResetChatId").value);
  if ($("attemptResetDay").value) payload.day = $("attemptResetDay").value.trim();
  const result = await fetchJson("/api/poker-admin/attempts-reset", {
    method: "POST",
    headers: tokenHeaders(true),
    body: JSON.stringify(payload),
  });
  $("pokerAdminOutput").textContent = JSON.stringify(result, null, 2);
  await loadPokerAdmin();
}

async function saveSetting(key) {
  const textarea = $(settingId(key));
  let value;
  try {
    value = JSON.parse(textarea.value);
  } catch (err) {
    $("pokerAdminOutput").textContent = `Invalid JSON for ${key}: ${err}`;
    return;
  }
  const result = await fetchJson(`/api/poker-admin/settings/${encodeURIComponent(key)}`, {
    method: "PUT",
    headers: tokenHeaders(true),
    body: JSON.stringify({value}),
  });
  $("pokerAdminOutput").textContent = JSON.stringify(result, null, 2);
  await loadPokerAdmin();
}

async function toggleBlock(userId, isBlocked) {
  const result = await fetchJson(`/api/poker-admin/users/${encodeURIComponent(userId)}/block`, {
    method: "PATCH",
    headers: tokenHeaders(true),
    body: JSON.stringify({is_blocked: isBlocked}),
  });
  $("pokerAdminOutput").textContent = JSON.stringify(result, null, 2);
  await loadPokerAdmin();
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => runAction(button.dataset.action).catch((err) => {
    $("actionOutput").textContent = String(err);
  }));
});

$("refresh").addEventListener("click", () => loadSummary().catch((err) => {
  $("serverState").textContent = String(err);
}));

$("login").addEventListener("click", () => login().catch((err) => {
  $("actionOutput").textContent = String(err);
}));
$("loginPassword").addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    login().catch((err) => {
      $("actionOutput").textContent = String(err);
    });
  }
});
$("logout").addEventListener("click", () => logout().catch((err) => {
  $("actionOutput").textContent = String(err);
}));

$("loadPokerAdmin").addEventListener("click", () => loadPokerAdmin().catch((err) => {
  $("pokerAdminOutput").textContent = String(err);
}));
$("adjustScore").addEventListener("click", () => submitScoreAdjust().catch((err) => {
  $("pokerAdminOutput").textContent = String(err);
}));
$("resetScores").addEventListener("click", () => submitScoreReset().catch((err) => {
  $("pokerAdminOutput").textContent = String(err);
}));
$("grantAttempts").addEventListener("click", () => submitAttemptsGrant().catch((err) => {
  $("pokerAdminOutput").textContent = String(err);
}));
$("resetAttempts").addEventListener("click", () => submitAttemptsReset().catch((err) => {
  $("pokerAdminOutput").textContent = String(err);
}));

async function boot() {
  await loadAuth().catch((err) => {
    auth = {configured: false, authenticated: false};
    updateAuthUi();
    $("actionOutput").textContent = String(err);
  });
  await loadSummary();
}

boot().catch((err) => {
  $("serverState").textContent = String(err);
});
