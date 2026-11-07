// The page: pairing card, offline copy, link, tabs. Thin on purpose; everything it calls is tested in Node.
import { pairWithPhone, openLink } from "../link-client.js";
import { toHex } from "../link-crypto.js";
import { createCache, idbStore, memoryStore } from "../cache.js";
import { createSync } from "../sync.js";
import { renderLibrary, renderStudy, renderStatus, renderAddWords, renderChanges, esc } from "./render.js";
import { renderArtifactList, renderArtifactPage } from "./artifacts.js";
import { createOutbox } from "../outbox.js";
import { sendOutboxItem, parseWords } from "../writes.js";
import { reasonText } from "../link-rpc.js";
import { makeT, pickLanguage, dirFor, errorText } from "./strings.js";

const $ = (s) => document.querySelector(s);

export async function start() {
  const state = { snapshot: null, takenAt: null, tab: "library", filters: {}, link: "connecting", message: "", reason: "", artifacts: { list: null, page: null, note: "" } };
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

  /** The main area for the current tab. */
  function body() {
    if (state.tab === "library") return renderAddWords(t) + renderLibrary(state.snapshot, state.filters, t);
    if (state.tab === "artifacts") {
      const a = state.artifacts;
      const note = a.note ? `<p class="muted">${esc(a.note)}</p>` : "";
      if (a.page) return note + renderArtifactPage(a.page, t);
      if (a.list) return note + renderArtifactList(a.list, t);
      return note || `<p class="muted">${t("Connecting…")}</p>`;
    }
    return renderStudy(state.snapshot, t);
  }

  /** Asks the phone for the artifact list or one page. Needs the live link: nothing here is kept in the browser. */
  async function loadArtifacts(id = null) {
    const link = sync?.link;
    if (!link) { state.artifacts.note = t("The phone must be connected to show artifacts."); paint(); return; }
    try {
      if (id) state.artifacts.page = (await link.request("artifact", { id })).result;
      else { state.artifacts.page = null; state.artifacts.list = (await link.request("artifacts")).result ?? []; }
      state.artifacts.note = "";
    } catch (e) {
      state.artifacts.note = t(reasonText(e?.kind ?? "failed"));
    }
    paint();
  }

  /** Why there is nothing to show yet, in words, with a way to try again. The tabs still work. */
  function emptyState() {
    const why = state.link === "connecting" ? t("Connecting…") : state.reason ? t(reasonText(state.reason)) : t("The phone did not answer. Keep Palabra open on screen.");
    return `<section class="empty"><h2>${esc(t("Nothing to show yet"))}</h2><p class="muted">${esc(why)}</p><button id="retry" class="chip">${esc(t("Try again"))}</button></section>`;
  }

  function paint() {
    $("#status").innerHTML = renderStatus({ state: state.link, takenAt: state.takenAt, message: state.message }, t);
    $("#view").innerHTML = state.tab !== "artifacts" && !state.snapshot ? emptyState()
      : body() + (state.tab === "artifacts" ? "" : renderChanges(changes, t, (r) => t(reasonText(r))));
    const retry = $("#retry");
    if (retry) retry.addEventListener("click", () => { if (pairing) sync?.start(pairing.secretHex, pairing.relayUrl); });
    for (const b of document.querySelectorAll("nav.tabs button")) {
      if (b.dataset.tab === state.tab) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
    }
    hint();
    for (const b of document.querySelectorAll("[data-artifact]")) b.addEventListener("click", () => loadArtifacts(b.dataset.artifact));
    const back = $("#artifactBack");
    if (back) back.addEventListener("click", () => { state.artifacts.page = null; paint(); });
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

  for (const b of document.querySelectorAll("nav.tabs button")) b.addEventListener("click", () => { state.tab = b.dataset.tab; paint(); if (state.tab === "artifacts" && !state.artifacts.page) loadArtifacts(); });

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
      cache, openLink: (options) => openLink({ ...options, timeoutMs: globalThis.PALABRA_RPC_TIMEOUT_MS ?? 15000 }),
      onChange: (v) => {
        Object.assign(state, { snapshot: v.snapshot, takenAt: v.takenAt, link: v.state, message: v.message, failures: v.failures, reason: v.reason });
        $("#pairing").hidden = true; $("#app").hidden = false; paint();     // always: with no data the page still shows the tabs and why
        if (v.state === "linked") outbox?.flush();      // the phone is back: send what waited, in order
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
