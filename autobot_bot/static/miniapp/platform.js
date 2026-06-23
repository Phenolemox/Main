// Universal Mini App adapter — works in Telegram WebApp and MAX Bridge.
// Telegram SDK exposes window.Telegram.WebApp; MAX Bridge exposes window.WebApp.
(function () {
  const tg = window.Telegram && window.Telegram.WebApp;
  const max = window.WebApp; // MAX Bridge global object
  const forced = new URLSearchParams(location.search).get("platform");

  let name = "web";
  if (forced === "max" && max) name = "max";
  else if (forced === "telegram" && tg) name = "telegram";
  else if (tg && (tg.initData || tg.platform)) name = "telegram";
  else if (max && (max.initData || max.platform)) name = "max";
  else if (tg) name = "telegram";
  else if (max) name = "max";

  const safe = (fn) => { try { return fn(); } catch (e) { return undefined; } };

  const MiniApp = {
    name,
    ready() { safe(() => tg && tg.ready && tg.ready()); safe(() => max && max.ready && max.ready()); },
    expand() { safe(() => tg && tg.expand && tg.expand()); },
    haptic(kind) {
      safe(() => tg && tg.HapticFeedback && tg.HapticFeedback.impactOccurred(kind || "light"));
      safe(() => max && max.HapticFeedback && max.HapticFeedback.impactOccurred && max.HapticFeedback.impactOccurred(kind || "light"));
    },
    close() { if (name === "telegram") safe(() => tg && tg.close && tg.close()); else safe(() => max && max.close && max.close()); },
    popup(opts) {
      if (name === "telegram" && tg && tg.showPopup) return safe(() => tg.showPopup(opts));
      const text = (opts && ((opts.title ? opts.title + "\n" : "") + (opts.message || ""))) || "";
      return safe(() => alert(text));
    },
    openBot(tgUrl, maxUrl) {
      if (name === "telegram" && tg && tg.openTelegramLink) return safe(() => tg.openTelegramLink(tgUrl));
      if (name === "max" && max && max.openMaxLink) return safe(() => max.openMaxLink(maxUrl || tgUrl));
      if (max && max.openLink) return safe(() => max.openLink(maxUrl || tgUrl));
      window.open(maxUrl || tgUrl, "_blank");
    },
    label() {
      if (name === "telegram") return "Telegram Mini App" + (tg && tg.platform ? " · " + tg.platform : "");
      if (name === "max") return "MAX Mini App" + (max && max.platform ? " · " + max.platform : "");
      return "Web Mini App";
    },
  };

  window.MiniApp = MiniApp;
  MiniApp.ready();
  MiniApp.expand();
})();
