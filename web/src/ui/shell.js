// The page: pairing card, offline copy, link, tabs. Thin on purpose; everything it calls is tested in Node.
import { pairWithPhoneFull, openLink, relayBase } from "../link-client.js";
import { toHex } from "../link-crypto.js";
import { createCache, idbStore, memoryStore } from "../cache.js";
import { createSync } from "../sync.js";
import { renderLibrary, renderStudy, renderStatus, renderAddWords, renderChanges, esc } from "./render.js";
import { renderArtifactList, renderArtifactPage } from "./artifacts.js";
import { renderChat, renderBooks, renderLesson } from "./chatbooks.js";
import { findPhones, requestTrust, renderFinder } from "../auto-pair.js";
import { createOutbox } from "../outbox.js";
import { sendOutboxItem, parseWords } from "../writes.js";
import { reasonText } from "../link-rpc.js";
import { makeT, pickLanguage, dirFor, errorText } from "./strings.js";
import { createDebugLog } from "../debug-log.js";
import { mountDebugPanel, environmentFacts } from "./debug-panel.js";

const $ = (s) => document.querySelector(s);

export async function start() {
  const state = { snapshot: null, takenAt: null, tab: "library", filters: {}, link: "connecting", message: "", reason: "", artifacts: { list: null, page: null, note: "" }, chat: { result: null, note: "" }, books: { list: null, lesson: null, note: "" } };
  const isFile = location.protocol === "file:";
  const lang = pickLanguage(navigator.languages?.length ? navigator.languages : [navigator.language]);
  const t = makeT(lang);
  document.documentElement.lang = lang;
  document.documentElement.dir = dirFor(lang);
  for (const node of document.querySelectorAll("[data-i18n]")) node.textContent = t(node.dataset.i18n);
  for (const node of document.querySelectorAll("[data-i18n-aria]")) node.setAttribute("aria-label", t(node.dataset.i18nAria));

  // Nothing is written to the browser unless the person ticks "Remember this computer".
  // The flight recorder starts before anything else so even a failure on the pairing screen is on record.
  const debug = createDebugLog();
  const log = debug.sink();
  for (const [area, text] of environmentFacts(globalThis)) debug.info(area, text);
  const hook = (target, type, fn) => { try { target?.addEventListener?.(type, fn); } catch { /* a missing hook only means less to read */ } };
  hook(globalThis, "error", (e) => debug.error("page", `uncaught error: ${e.message || "unknown"}`, e.filename ? `${String(e.filename).split("/").pop()}:${e.lineno}` : undefined));
  hook(globalThis, "unhandledrejection", (e) => debug.error("page", "unhandled promise rejection", e.reason?.message ?? e.reason?.kind ?? e.reason));
  hook(globalThis, "online", () => debug.info("page", "the browser went online"));
  hook(globalThis, "offline", () => debug.warn("page", "the browser went offline"));
  hook(document, "visibilitychange", () => debug.info("page", `tab is now ${document.visibilityState}`));
  const copyText = async (text) => {
    try { await navigator.clipboard.writeText(text); return true; }
    catch { try { const area = document.createElement("textarea"); area.value = text; document.body.append(area); area.select(); const ok = document.execCommand("copy"); area.remove(); return ok; } catch { return false; } }
  };
  let remembered = false;
  const memory = createCache(memoryStore());
  const disk = (() => { try { return createCache(idbStore()); } catch { return memory; } })();
  let cache = memory;

  const STUCK_AFTER = 4;   // failed attempts in a row before suggesting the pairing may have been removed on the phone
  function hint() {
    const stuck = (state.failures ?? 0) >= STUCK_AFTER && (state.link === "away" || state.link === "empty");
    const key = stuck ? "Phone not answering. Keep Palabra open on the phone screen (it disconnects when you leave the app or lock the phone). If it still fails, press Debug and send me the log."
      : state.link === "away" ? "Saved copy from your phone. Keep Palabra open on the phone screen to update: it disconnects when you leave the app or lock the phone."
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
    if (state.tab === "chat") {
      const c = state.chat;
      const note = c.note ? `<p class="muted">${esc(c.note)}</p>` : "";
      return c.result ? note + renderChat(c.result, t) : note || `<p class="muted">${t("Connecting…")}</p>`;
    }
    if (state.tab === "books") {
      const b = state.books;
      const note = b.note ? `<p class="muted">${esc(b.note)}</p>` : "";
      if (b.lesson) return note + renderLesson(b.lesson, t);
      return b.list ? note + renderBooks(b.list, t) : note || `<p class="muted">${t("Connecting…")}</p>`;
    }
    return renderStudy(state.snapshot, t);
  }

  /** Asks the phone for its latest chat. Live link only; nothing is kept in the browser. */
  async function loadChat() {
    const link = sync?.link;
    if (!link) { state.chat.note = t("The phone must be connected to show this."); paint(); return; }
    try { state.chat.result = (await link.request("chat")).result; state.chat.note = ""; }
    catch (e) { state.chat.note = t(reasonText(e?.kind ?? "failed")); }
    paint();
  }

  /** Asks the phone for the book list, or for one lesson. */
  async function loadBooks(book = null, lesson = null) {
    const link = sync?.link;
    if (!link) { state.books.note = t("The phone must be connected to show this."); paint(); return; }
    try {
      if (book && lesson) state.books.lesson = (await link.request("lesson", { book, lesson })).result;
      else { state.books.lesson = null; state.books.list = (await link.request("books")).result ?? []; }
      state.books.note = "";
    } catch (e) { state.books.note = t(reasonText(e?.kind ?? "failed")); }
    paint();
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
    const why = state.link === "connecting" ? t(state.step === "phone" ? "Reached the relay. Waiting for the phone… Keep Palabra open on it." : "Reaching the relay…") : state.reason ? t(reasonText(state.reason)) : t(reasonText("no-answer"));
    return `<section class="empty"><h2>${esc(t("Nothing to show yet"))}</h2><p class="muted">${esc(why)}</p><button id="retry" class="chip">${esc(t("Try again"))}</button></section>`;
  }

  function paint() {
    $("#status").innerHTML = renderStatus({ state: state.link, takenAt: state.takenAt, message: state.message }, t);
    $("#view").innerHTML = !["artifacts", "chat", "books"].includes(state.tab) && !state.snapshot ? emptyState()
      : body() + (["artifacts", "chat", "books"].includes(state.tab) ? "" : renderChanges(changes, t, (r) => t(reasonText(r))));
    const retry = $("#retry");
    if (retry) retry.addEventListener("click", () => { if (pairing) sync?.start(pairing.secretHex, pairing.relayUrl); });
    for (const b of document.querySelectorAll("nav.tabs button")) {
      if (b.dataset.tab === state.tab) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
    }
    hint();
    for (const b of document.querySelectorAll("[data-artifact]")) b.addEventListener("click", () => loadArtifacts(b.dataset.artifact));
    for (const b of document.querySelectorAll("[data-lesson]")) b.addEventListener("click", () => loadBooks(b.dataset.book, b.dataset.lesson));
    const lessonBack = $("#lessonBack");
    if (lessonBack) lessonBack.addEventListener("click", () => { state.books.lesson = null; paint(); });
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

  for (const b of document.querySelectorAll("nav.tabs button")) b.addEventListener("click", () => { state.tab = b.dataset.tab; paint(); if (state.tab === "artifacts" && !state.artifacts.page) loadArtifacts(); if (state.tab === "chat") loadChat(); if (state.tab === "books" && !state.books.lesson) loadBooks(); });

  let sync = null, pairing = null, outbox = null, changes = { queue: [], review: [] };
  function begin(pair) {
    log("page", `starting a link (${pair.tokenHex ? "trusted computer" : "paired with the code"}, ${remembered ? "remembered on this computer" : "kept in memory only"})`);
    pairing = pair;
    sync?.stop();
    outbox = createOutbox({
      store: cache.store, send: sendOutboxItem(() => sync?.link ?? null),
      onChange: (c) => { changes = c; if (state.snapshot) paint(); },
    });
    outbox.load();
    sync = createSync({
      cache, log, openLink: (options) => openLink({ ...options, log, tokenHex: pair.tokenHex ?? null, timeoutMs: globalThis.PALABRA_RPC_TIMEOUT_MS ?? 15000 }),
      onChange: (v) => {
        Object.assign(state, { snapshot: v.snapshot, takenAt: v.takenAt, link: v.state, message: v.message, failures: v.failures, reason: v.reason, step: v.step });
        $("#pairing").hidden = true; $("#app").hidden = false; paint();     // always: with no data the page still shows the tabs and why
        if (v.state === "linked") outbox?.flush();      // the phone is back: send what waited, in order
      },
    });
    return sync.showCached().then(() => sync.start(pair.secretHex, pair.relayUrl));   // saved copy first, then the phone
  }

  $("#sync").addEventListener("click", () => { log("click", "Sync now"); sync?.refresh(); });
  $("#forget").addEventListener("click", async () => {
    sync?.stop(); sync = null; pairing = null;
    await disk.clearAll(); await memory.clearAll();
    await outbox?.clear(); outbox = null; changes = { queue: [], review: [] };
    Object.assign(state, { snapshot: null, takenAt: null, link: "idle" });
    $("#app").hidden = true; $("#pairing").hidden = false; $("#view").innerHTML = ""; $("#err").textContent = "";
  });


  // Find my phone: look through the relay for phones on this network, ask one to trust this computer, then carry on like the code path.
  const finder = { state: "idle", phones: [], code: "", message: "" };
  const paintFinder = () => { $("#found").innerHTML = renderFinder(finder, t, esc); wireFinder(); };
  function wireFinder() {
    for (const b of document.querySelectorAll("[data-phone]")) b.addEventListener("click", () => choosePhone(finder.phones.find((p) => p.deviceId === b.dataset.phone)));
  }
  async function choosePhone(phone) {
    if (!phone) return;
    Object.assign(finder, { state: "waiting", code: "" }); paintFinder();
    try {
      const got = await requestTrust({ relayUrl: $("#relay").value.trim(), phone, log, onCode: (c) => { finder.code = c; paintFinder(); } });
      const pair = { secretHex: toHex(got.secret), relayUrl: relayBase(got.relayUrl || $("#relay").value.trim()), tokenHex: toHex(got.token), deviceId: got.deviceId };
      remembered = $("#remember").checked;
      cache = remembered ? disk : memory;
      if (remembered) await disk.savePairing(pair);
      finder.state = "idle"; paintFinder();
      await begin(pair);
    } catch (e) {
      Object.assign(finder, { state: "error", message: errorText(e, t) }); paintFinder();
    }
  }
  $("#find").addEventListener("click", async () => {
    log("click", "Find my phone");
    const relay = $("#relay").value.trim();
    if (!relay) { Object.assign(finder, { state: "error", message: t("Type the relay address first, so the search knows where to look.") }); return paintFinder(); }
    Object.assign(finder, { state: "searching", phones: [] }); paintFinder();
    try {
      finder.phones = await findPhones({ relayUrl: relay, log });
      finder.state = finder.phones.length ? "list" : "none";
    } catch (e) { Object.assign(finder, { state: "error", message: errorText(e, t) }); }
    paintFinder();
  });

  $("#pair").addEventListener("submit", async (event) => {
    event.preventDefault();
    log("click", "Connect (pair with the code)");
    const go = $("#go"); go.disabled = true; $("#err").textContent = "";
    try {
      const { secret, relayUrl: fromPhone } = await pairWithPhoneFull({ address: $("#address").value, code: $("#code").value.trim(), isFileOrigin: isFile, log });
      // The phone says which relay it is on; that wins over anything typed here, so the two ends cannot end up on different relays.
      const typed = $("#relay").value.trim();
      const chosen = fromPhone || typed;
      if (!chosen) throw { kind: "relay-address", message: "Type the relay address, like wss://palabra-relay.yourname.workers.dev" };
      const pair = { secretHex: toHex(secret), relayUrl: relayBase(chosen) };
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

  // The console must never be able to break the page: if it cannot be built, the page carries on and keeps logging.
  try {
    if (typeof document.createElement === "function" && document.body) {
      mountDebugPanel({ doc: document, log: debug, t, copyText, getStatus: () => ({ link: state.link, step: state.step, failures: state.failures, reason: state.reason, takenAt: state.takenAt }) });
    }
  } catch (e) { debug.error("page", "the debug console could not be built", e); }
  debug.info("page", `ready (language ${lang})`);

  // A remembered computer opens straight onto its saved copy, then reconnects on its own.
  const saved = await disk.loadPairing();
  if (saved?.relayUrl) $("#relay").value = saved.relayUrl;
  if (saved) {
    remembered = true; cache = disk;
    await begin({ secretHex: saved.secretHex, relayUrl: saved.relayUrl, tokenHex: saved.tokenHex });
  }
}
