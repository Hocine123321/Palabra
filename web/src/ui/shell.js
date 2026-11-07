// The page: pairing card, offline copy, link, tabs. Thin on purpose; everything it calls is tested in Node.
import { pairWithPhone, openLink } from "../link-client.js";
import { toHex } from "../link-crypto.js";
import { createCache, idbStore, memoryStore } from "../cache.js";
import { createSync } from "../sync.js";
import { renderLibrary, renderStudy, renderStatus, renderAddWords, renderChanges } from "./render.js";
import { createOutbox } from "../outbox.js";
import { sendOutboxItem, parseWords } from "../writes.js";
import { reasonText } from "../link-rpc.js";
import { makeT, pickLanguage, dirFor, errorText } from "./strings.js";

const $ = (s) => document.querySelector(s);

export async function start() {
  const state = { snapshot: null, takenAt: null, tab: "library", filters: {}, link: "connecting", message: "" };
  const isFile = location.protocol === "file:";
  const lang = pickLanguage(navigator.languages?.length ? navigator.languages : [navigator.language]);
  const t = makeT(lang);
  document.documentElement.lang = lang;
  document.documentElement.dir = dirFor(lang);
  for (const node of document.querySelectorAll("[data-i18n]")) node.textContent = t(node.dataset.i18n);
  for (const node of document.querySelectorAll("[data-i18n-aria]")) node.setAttribute("aria-label", t(node.dataset.i18nAria));

  // Nothing is written to the browser unless the person ticks "Remember this computer".
  let remembered = false;
  const memory = createCache(memoryStore());
  const disk = (() => { try { return createCache(idbStore()); } catch { return memory; } })();
  let cache = memory;

  const STUCK_AFTER = 4;   // failed attempts in a row before suggesting the pairing may have been removed on the phone
  function hint() {
    const stuck = (state.failures ?? 0) >= STUCK_AFTER && (state.link === "away" || state.link === "empty");
    const key = stuck ? "Phone not answering. If you removed this browser in the app, forget this computer and pair again."
      : state.link === "away" ? "Saved copy from your phone. Open Palabra on the phone to update."
      : state.link === "empty" ? "Nothing saved yet. Connect to your phone first." : "";
    $("#hint").textContent = key ? t(key) : "";
  }

  function paint() {
    if (!state.snapshot) return;
    $("#status").innerHTML = renderStatus({ state: state.link, takenAt: state.takenAt, message: state.message }, t);
    $("#view").innerHTML = (state.tab === "library" ? renderAddWords(t) + renderLibrary(state.snapshot, state.filters, t) : renderStudy(state.snapshot, t))
      + renderChanges(changes, t, (r) => t(reasonText(r)));
    for (const b of document.querySelectorAll("nav.tabs button")) {
      if (b.dataset.tab === state.tab) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
    }
    hint();
    const add = $("#add");
    if (add) add.addEventListener("submit", async (e) => {
      e.preventDefault();
      const words = parseWords($("#addText").value);
      if (!words.length || !outbox) return;
      await outbox.enqueue("words.add", { words });
      $("#addText").value = "";
      outbox.flush();
    });
    for (const b of document.querySelectorAll("[data-cancel]")) b.addEventListener("click", () => outbox.cancel(b.dataset.cancel));
    for (const b of document.querySelectorAll("[data-retry]")) b.addEventListener("click", async () => { await outbox.retry(b.dataset.retry); outbox.flush(); });
    for (const b of document.querySelectorAll("[data-drop]")) b.addEventListener("click", () => outbox.drop(b.dataset.drop));
    const search = $("#search");
    if (search) search.addEventListener("input", (e) => {
      state.filters.query = e.target.value; const at = e.target.selectionStart; paint();
      const again = $("#search"); again.focus(); again.setSelectionRange(at, at);
    });
    for (const c of document.querySelectorAll(".chip[data-tag]")) c.addEventListener("click", () => { state.filters.tag = c.dataset.tag || null; paint(); });
  }

  for (const b of document.querySelectorAll("nav.tabs button")) b.addEventListener("click", () => { state.tab = b.dataset.tab; paint(); });

  let sync = null, pairing = null, outbox = null, changes = { queue: [], review: [] };
  function begin(pair) {
    pairing = pair;
    sync?.stop();
    outbox = createOutbox({
      store: cache.store, send: sendOutboxItem(() => sync?.link ?? null),
      onChange: (c) => { changes = c; if (state.snapshot) paint(); },
    });
    outbox.load();
    sync = createSync({
      cache, openLink,
      onChange: (v) => {
        Object.assign(state, { snapshot: v.snapshot, takenAt: v.takenAt, link: v.state, message: v.message, failures: v.failures });
        if (v.snapshot) { $("#pairing").hidden = true; $("#app").hidden = false; paint(); }
        if (v.state === "linked") outbox?.flush();      // the phone is back: send what waited, in order
        else if (v.state === "empty") { $("#pairing").hidden = true; $("#app").hidden = false; $("#status").innerHTML = renderStatus({ state: "away", takenAt: null }, t); hint(); $("#view").innerHTML = ""; }
      },
    });
    return sync.showCached().then(() => sync.start(pair.secretHex, pair.relayUrl));   // saved copy first, then the phone
  }

  $("#sync").addEventListener("click", () => sync?.refresh());
  $("#forget").addEventListener("click", async () => {
    sync?.stop(); sync = null; pairing = null;
    await disk.clearAll(); await memory.clearAll();
    await outbox?.clear(); outbox = null; changes = { queue: [], review: [] };
    Object.assign(state, { snapshot: null, takenAt: null, link: "idle" });
    $("#app").hidden = true; $("#pairing").hidden = false; $("#view").innerHTML = ""; $("#err").textContent = "";
  });

  $("#pair").addEventListener("submit", async (event) => {
    event.preventDefault();
    const go = $("#go"); go.disabled = true; $("#err").textContent = "";
    try {
      const secret = await pairWithPhone({ address: $("#address").value, code: $("#code").value.trim(), isFileOrigin: isFile });
      const pair = { secretHex: toHex(secret), relayUrl: $("#relay").value.trim() };
      remembered = $("#remember").checked;
      cache = remembered ? disk : memory;
      if (remembered) await disk.savePairing(pair);
      $("#code").value = "";
      await begin(pair);
    } catch (e) {
      $("#pairing").hidden = false; $("#app").hidden = true;
      $("#err").textContent = errorText(e, t);
    } finally { go.disabled = false; }
  });

  // A remembered computer opens straight onto its saved copy, then reconnects on its own.
  const saved = await disk.loadPairing();
  if (saved) {
    remembered = true; cache = disk;
    await begin({ secretHex: saved.secretHex, relayUrl: saved.relayUrl });
  }
}
