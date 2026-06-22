const $ = (id) => document.getElementById(id);

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

async function loadSummary() {
  const res = await fetch("/api/summary");
  if (!res.ok) throw new Error(`summary ${res.status}`);
  const data = await res.json();
  render(data);
}

function render(data) {
  $("generatedAt").textContent = data.generated_at;
  $("actionState").innerHTML = data.write_actions_configured
    ? pill(true, "write actions ready")
    : pill(false, "token not configured");

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

  $("poker").innerHTML = data.health
    .filter((h) => h.name.startsWith("poker"))
    .map((h) => `
      <div class="row">
        <strong>${esc(h.name)}</strong>
        <p>${pill(h.result.ok, h.result.ok ? "ok" : "error")} <span class="muted">${h.result.latency_ms || 0} ms</span></p>
        <pre class="terminal">${esc(JSON.stringify(h.result.body ?? h.result.error, null, 2))}</pre>
      </div>
    `).join("");

  $("panels").innerHTML = data.panels.map((p) => `
    <a href="${esc(p.url)}" target="_blank" rel="noreferrer">
      <strong>${esc(p.name)}</strong>
      <div class="muted">${esc(p.kind)} · ${esc(p.url)}</div>
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
  const token = $("token").value;
  $("actionOutput").textContent = `Running ${action}...`;
  const res = await fetch(`/api/actions/${action}`, {
    method: "POST",
    headers: token ? {"X-Control-Room-Token": token} : {},
  });
  const text = await res.text();
  $("actionOutput").textContent = text;
  await loadSummary();
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => runAction(button.dataset.action).catch((err) => {
    $("actionOutput").textContent = String(err);
  }));
});

$("refresh").addEventListener("click", () => loadSummary().catch((err) => {
  $("serverState").textContent = String(err);
}));

loadSummary().catch((err) => {
  $("serverState").textContent = String(err);
});
