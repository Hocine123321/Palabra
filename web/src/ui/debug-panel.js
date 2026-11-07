// The Debug console: a floating button that opens a panel showing everything the page is doing. Thin on purpose; the log itself
// (debug-log.js) is tested in Node. Every entry is text-only (textContent), never markup, so nothing in the log can run as script.

/** Facts that explain most connection problems, written to the top of the log when the page starts. */
export function environmentFacts(win) {
  const nav = win.navigator ?? {};
  const loc = win.location ?? {};
  return [
    ["page", `opened from ${loc.protocol || "?"}//${loc.host || ""}`],
    ["page", `secure context: ${win.isSecureContext ? "yes" : "NO (some browser features are unavailable)"}`],
    ["page", `WebSocket: ${typeof win.WebSocket === "function" ? "available" : "MISSING"}, crypto.subtle: ${win.crypto?.subtle ? "available" : "MISSING"}, IndexedDB: ${win.indexedDB ? "available" : "no"}`],
    ["page", `online: ${nav.onLine === false ? "NO (the browser says it is offline)" : "yes"}, language: ${nav.language || "?"}`],
    ["page", `browser: ${String(nav.userAgent || "?").slice(0, 120)}`],
  ];
}

import { verdict } from "./debug-verdict.js";

export function mountDebugPanel({ doc, log, t, getStatus, copyText, now = () => Date.now() }) {
  const button = doc.createElement("button");
  button.id = "debug-open"; button.type = "button"; button.className = "debug-fab";
  button.setAttribute("aria-label", t("Debug")); button.title = t("Debug"); button.setAttribute("aria-haspopup", "dialog");
  const dot = doc.createElement("span"); dot.className = "debug-dot"; button.append(dot);
  const glyph = doc.createElement("span"); glyph.className = "debug-glyph"; glyph.textContent = "🛠"; glyph.setAttribute("aria-hidden", "true"); button.append(glyph);

  const panel = doc.createElement("section");
  panel.id = "debug-panel"; panel.className = "debug-panel glass"; panel.hidden = true;
  panel.setAttribute("role", "dialog"); panel.setAttribute("aria-label", t("Debug console"));
  panel.innerHTML = `
    <div class="debug-head"><strong></strong><button type="button" class="debug-x" data-d="close"></button></div>
    <div class="debug-verdict" data-tone="wait"><span class="debug-dot"></span><div><p class="debug-title"></p><p class="debug-help"></p></div></div>
    <button type="button" class="primary debug-copy" data-d="copy"></button>
    <button type="button" class="debug-more" data-d="more" aria-expanded="false"></button>
    <div class="debug-details" hidden>
      <dl class="debug-status" aria-live="off"></dl>
      <div class="debug-filters"><input type="search" data-d="filter" autocomplete="off" spellcheck="false"><select data-d="level"></select></div>
      <pre class="debug-log" tabindex="0" dir="ltr"></pre>
      <div class="debug-tools"><button type="button" class="chip" data-d="pause"></button><button type="button" class="chip" data-d="clear"></button></div>
      <p class="muted small debug-note"></p>
    </div>`;
  const q = (s) => panel.querySelector(s);
  q(".debug-head strong").textContent = t("Debug console");
  q('[data-d="copy"]').textContent = t("Copy for support"); q('[data-d="clear"]').textContent = t("Clear");
  q('[data-d="close"]').textContent = "✕"; q('[data-d="close"]').setAttribute("aria-label", t("Close")); q('[data-d="pause"]').textContent = t("Pause");
  q('[data-d="more"]').textContent = t("Show details");
  q('[data-d="filter"]').placeholder = t("Filter, for example rx or presence");
  q('[data-d="filter"]').setAttribute("aria-label", t("Filter, for example rx or presence"));
  for (const [value, label] of [["", "All"], ["warn", "Warnings and errors"], ["error", "Errors only"]]) {
    const option = doc.createElement("option"); option.value = value; option.textContent = t(label); q('[data-d="level"]').append(option);
  }
  q(".debug-note").textContent = t("The log never contains your words, codes or keys. Long keys are cut short and message contents are only described by type and size.");
  doc.body.append(button, panel);

  let paused = false, stick = true;
  const out = q(".debug-log");
  const filters = () => ({ filter: q('[data-d="filter"]').value, level: q('[data-d="level"]').value });

  function paintVerdict() {
    const s = getStatus?.() ?? {};
    const v = verdict({ link: s.link, reason: s.reason, failures: s.failures, online: doc.defaultView?.navigator?.onLine !== false });
    const box = q(".debug-verdict"); box.setAttribute("data-tone", v.tone);
    q(".debug-title").textContent = t(v.title); q(".debug-help").textContent = t(v.help);
    button.setAttribute("data-tone", v.tone);
  }
  function paintStatus() {
    paintVerdict();
    const s = getStatus?.() ?? {};
    const rows = [
      [t("Link"), s.link ?? "?"], [t("Step"), s.step || "-"], [t("Failed attempts"), String(s.failures ?? 0)],
      [t("Last reason"), s.reason || "-"], [t("Saved copy"), s.takenAt ? String(s.takenAt) : "-"],
      [t("Last event"), log.entries.length ? `${Math.max(0, Math.round((now() - log.entries.at(-1).at) / 1000))}s` : "-"],
    ];
    const list = q(".debug-status"); list.textContent = "";
    for (const [k, v] of rows) { const dt = doc.createElement("dt"), dd = doc.createElement("dd"); dt.textContent = k; dd.textContent = v; list.append(dt, dd); }
  }
  function paintLog() {
    out.textContent = log.toText(filters()) || t("Nothing logged yet.");
    if (stick) out.scrollTop = out.scrollHeight;
  }
  const paintAll = () => { paintStatus(); paintLog(); };

  q('[data-d="more"]').addEventListener("click", () => {
    const details = q(".debug-details"); details.hidden = !details.hidden;
    q('[data-d="more"]').textContent = t(details.hidden ? "Show details" : "Hide details");
    q('[data-d="more"]').setAttribute("aria-expanded", String(!details.hidden)); if (!details.hidden) paintLog();
  });
  const unsubscribe = log.onEntry(() => { if (!panel.hidden && !paused) { paintLog(); paintStatus(); } });
  const ticker = setInterval(() => { if (!panel.hidden) paintStatus(); }, 1000);
  out.addEventListener("scroll", () => { stick = out.scrollTop + out.clientHeight >= out.scrollHeight - 8; });
  q('[data-d="filter"]').addEventListener("input", paintLog);
  q('[data-d="level"]').addEventListener("change", paintLog);
  q('[data-d="clear"]').addEventListener("click", () => { log.clear(); log.info("debug", "log cleared"); paintAll(); });
  q('[data-d="pause"]').addEventListener("click", () => {
    paused = !paused; q('[data-d="pause"]').textContent = t(paused ? "Resume" : "Pause"); if (!paused) paintAll();
  });
  q('[data-d="copy"]').addEventListener("click", async () => {
    const header = `Palabra web debug log, ${new Date(now()).toISOString()}\n`;
    const status = Object.entries(getStatus?.() ?? {}).filter(([k]) => ["link", "step", "failures", "reason"].includes(k)).map(([k, v]) => `${k}=${v}`).join(" ");
    const ok = await copyText(`${header}${status}\n${log.toText({})}`);
    const copy = q('[data-d="copy"]'); copy.textContent = t(ok ? "Copied" : "Select the log and copy it by hand");
    setTimeout(() => { copy.textContent = t("Copy for support"); }, 2500);
  });
  const open = () => { panel.hidden = false; button.setAttribute("aria-expanded", "true"); stick = true; paintAll(); q('[data-d="copy"]').focus(); };
  const close = () => { panel.hidden = true; button.setAttribute("aria-expanded", "false"); button.focus(); };
  button.addEventListener("click", () => (panel.hidden ? open() : close()));
  q('[data-d="close"]').addEventListener("click", close);
  panel.addEventListener("keydown", (e) => { if (e.key === "Escape") close(); });

  paintVerdict();
  return { open, close, button, panel, destroy() { unsubscribe(); clearInterval(ticker); button.remove(); panel.remove(); } };
}
