async function fetchJson(url) {
  const res = await fetch(url, { cache: "no-store" });
  if (!res.ok) throw new Error(String(res.status));
  return res.json();
}

function esc(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

async function loadBots() {
  // Health is computed server-side (hub queries internal URLs and returns status).
  // The browser only ever talks to same-origin /api/bots over HTTPS.
  const data = await fetchJson("/api/bots");
  const botsEl = document.getElementById("bots");
  const statsEl = document.getElementById("stats");

  botsEl.innerHTML = "";
  for (const bot of data.items) {
    const online = bot.health && bot.health.online;
    const card = document.createElement("article");
    card.className = "bot-card";
    card.innerHTML = `
      <div class="bot-head">
        <div class="emoji">${esc(bot.emoji)}</div>
        <div>
          <h2>${esc(bot.name)}</h2>
          <div class="status ${online ? "good" : "bad"}">${online ? "online" : "offline"}</div>
        </div>
      </div>
      <p class="desc">${esc(bot.description)}</p>
      <div class="links">
        <a href="${esc(bot.miniapp_url)}" target="_blank" rel="noopener">Mini App</a>
        <a href="${esc(bot.miniapp_url)}?platform=max" target="_blank" rel="noopener">MAX</a>
        <a href="${esc(bot.telegram)}" target="_blank" rel="noopener">Telegram</a>
        <a href="${esc(bot.public)}/health" target="_blank" rel="noopener">Health</a>
      </div>`;
    botsEl.appendChild(card);
  }

  statsEl.innerHTML = `
    <div class="stat"><div class="num">${data.total}</div><div class="label">ботов</div></div>
    <div class="stat"><div class="num">${data.online}</div><div class="label">online</div></div>
    <div class="stat"><div class="num">${data.offline}</div><div class="label">offline</div></div>`;
}

document.getElementById("refresh").addEventListener("click", () => loadBots().catch(console.error));
loadBots().catch(console.error);
setInterval(() => loadBots().catch(console.error), 30000);
