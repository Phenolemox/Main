async function fetchJson(url) {
  const res = await fetch(url, { cache: "no-store" });
  if (!res.ok) throw new Error(String(res.status));
  return res.json();
}

function esc(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

async function loadBots() {
  const data = await fetchJson("/api/bots");
  const botsEl = document.getElementById("bots");
  const statsEl = document.getElementById("stats");
  let online = 0;

  botsEl.innerHTML = "";
  for (const bot of data.items) {
    let health = { status: "unknown" };
    try {
      health = await fetchJson(bot.health_url);
      if (health.status === "healthy") online += 1;
    } catch (_err) {
      health = { status: "offline" };
    }
    const card = document.createElement("article");
    card.className = "bot-card";
    card.innerHTML = `
      <div class="bot-head">
        <div class="emoji">${esc(bot.emoji)}</div>
        <div>
          <h2>${esc(bot.name)}</h2>
          <div class="status ${health.status === "healthy" ? "good" : "bad"}">${health.status === "healthy" ? "online" : "offline"}</div>
        </div>
      </div>
      <p class="desc">${esc(bot.description)}</p>
      <div class="links">
        <a href="${esc(bot.miniapp_url)}" target="_blank" rel="noopener">Mini App</a>
        <a href="${esc(bot.telegram)}" target="_blank" rel="noopener">Telegram</a>
        <a href="${esc(bot.health_url)}" target="_blank" rel="noopener">Health</a>
      </div>`;
    botsEl.appendChild(card);
  }

  statsEl.innerHTML = `
    <div class="stat"><div class="num">${data.items.length}</div><div class="label">ботов</div></div>
    <div class="stat"><div class="num">${online}</div><div class="label">online</div></div>
    <div class="stat"><div class="num">${data.items.length - online}</div><div class="label">offline</div></div>`;
}

document.getElementById("refresh").addEventListener("click", () => loadBots().catch(console.error));
loadBots().catch(console.error);
