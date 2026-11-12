// Screens as plain element trees, and a mount that builds DOM with createElement and text nodes only
// (no innerHTML, no inline styles: the page's CSP forbids both, and nothing from the phone is ever treated as markup).
import { qrTree } from "./qr.js";
import { formatTime } from "./render/util.js";
import { t } from "./strings.js";

/** h("button", {class: "x", onClick: fn}, "text") -> {tag, attrs, handlers, children}. Functions never become attributes. */
export function h(tag, attrs = {}, ...children) {
  const plain = {};
  const handlers = {};
  for (const [name, value] of Object.entries(attrs ?? {})) {
    if (typeof value === "function") handlers[name.replace(/^on/, "").toLowerCase()] = value;
    else if (value !== undefined && value !== null && value !== false) plain[name] = String(value);
  }
  return { tag, attrs: plain, handlers, children: children.flat().filter((c) => c !== null && c !== undefined && c !== false) };
}

const SVG_NS = "http://www.w3.org/2000/svg";
const SVG_TAGS = new Set(["svg", "path", "rect", "title"]);
const FORBIDDEN_ATTR = /^(on|style$|innerhtml$|srcdoc$)/i;

export function mount(root, tree, doc = globalThis.document) {
  const build = (node) => {
    if (typeof node === "string") return doc.createTextNode(node);
    const el = SVG_TAGS.has(node.tag) ? doc.createElementNS(SVG_NS, node.tag) : doc.createElement(node.tag);
    for (const [name, value] of Object.entries(node.attrs ?? {})) {
      if (!FORBIDDEN_ATTR.test(name)) el.setAttribute(name, value);
    }
    for (const [type, fn] of Object.entries(node.handlers ?? {})) el.addEventListener(type, fn);
    for (const child of node.children ?? []) el.append(build(child));
    return el;
  };
  root.replaceChildren(build(tree));
}

const button = (text, onClick, extra = {}) => h("button", { type: "button", class: "button", onClick, ...extra }, text);

export function pairScreen({ link, status, lang, onCancel, onRestart }, tr = t) {
  const waiting = status === "waiting";
  const message = { expired: "Pairing expired.", cancelled: "Pairing was cancelled.", error: "Something went wrong. Try again." }[status];
  return h(
    "main",
    { class: "screen", lang },
    h("h1", {}, tr("Pair this computer", lang)),
    waiting ? h("p", { class: "secondary" }, tr("On your phone open Palabra, then Settings, Mirroring, Pair a Computer, and scan this code.", lang)) : null,
    waiting ? h("div", { class: "qr-box" }, qrTree(link)) : null,
    waiting ? h("p", { class: "status" }, tr("Waiting for your phone…", lang)) : null,
    message ? h("p", { class: "status", role: "alert" }, tr(message, lang)) : null,
    waiting ? button(tr("Cancel", lang), onCancel, { class: "button secondary-button" }) : button(tr("Start again", lang), onRestart, { id: "restart" }),
  );
}

export function confirmScreen({ code, lang, waiting, onMatch, onCancel }, tr = t) {
  return h(
    "main",
    { class: "screen", lang },
    h("h1", {}, tr("Check the code", lang)),
    h("p", { class: "code", dir: "ltr", "aria-label": code }, code),
    h("p", { class: "secondary" }, tr("The code on your phone and on this screen must be the same. If they differ, cancel.", lang)),
    waiting ? h("p", { class: "status" }, tr("Waiting for your phone to confirm…", lang)) : button(tr("Codes match", lang), onMatch, { id: "codes-match" }),
    button(tr("Cancel", lang), onCancel, { class: "button secondary-button" }),
  );
}

const DAY_MS = 24 * 3_600_000;
const ROLLBACK_TEXT = "The server sent older data than this computer already has, so it was ignored. Showing your saved copy.";
const NO_FRESHNESS = { state: "unverified", pushedAt: null, rollback: false };

/** The lines about the phone's data: when it last synced, whether the copy is complete, and the replay banner. */
function freshnessLines({ freshness, status, lang, now }, tr) {
  const { state, pushedAt, rollback } = { ...NO_FRESHNESS, ...(freshness ?? {}) };
  const when = Number.isFinite(pushedAt) ? formatTime(pushedAt, lang) : "";
  const stale = Number.isFinite(pushedAt) && now() - pushedAt > DAY_MS;
  return [
    rollback || status === "rollback" ? h("p", { class: "status", role: "alert" }, tr(ROLLBACK_TEXT, lang)) : null,
    when ? h("p", { class: "secondary" }, `${tr("Phone synced", lang)}: ${when}`) : null,
    state === "incomplete" ? h("p", { class: "status", role: "status" }, tr("Still receiving from your phone…", lang)) : null,
    state === "unverified" ? h("p", { class: "secondary" }, tr("Not verified yet", lang)) : null,
    stale ? h("p", { class: "status stale" }, tr("The phone has not synced for over a day, so this may be out of date.", lang)) : null,
  ];
}

/**
 * What every screen of the signed-in page has: the navigation bar, a title with the Refresh button, when this computer last
 * updated, the status line and the phone's freshness lines. `body` is the screen itself.
 */
export function screenFrame({ title, titleDir, nav, syncedAt = null, status = null, freshness, lang, onRefresh, now = Date.now }, tr, ...body) {
  const statusText = { offline: "Offline: showing your saved copy.", error: "Could not update. Showing your saved copy.", syncing: "Updating…" }[status];
  return h(
    "main",
    { class: "screen", lang },
    nav ?? null,
    h("header", { class: "bar" }, h("h1", { dir: titleDir ?? null }, title), button(tr("Refresh", lang), onRefresh, { id: "refresh", class: "button secondary-button" })),
    h("p", { class: "secondary" }, syncedAt ? `${tr("Last updated", lang)}: ${formatTime(syncedAt, lang)}` : tr("Not updated yet", lang)),
    statusText ? h("p", { class: "status", role: "status" }, tr(statusText, lang)) : null,
    ...freshnessLines({ freshness, status, lang, now }, tr),
    ...body,
  );
}

export function wordsScreen({ words, syncedAt, status = null, freshness, lang, onRefresh, now = Date.now, nav = null }, tr = t) {
  const rows = words.map((w) =>
    h(
      "li",
      { class: "row" },
      typeof w.id === "string" && w.id ? h("a", { class: "headword", dir: "auto", href: `#/words/${w.id}` }, String(w.spanish ?? "")) : h("span", { class: "headword", dir: "auto" }, String(w.spanish ?? "")),
      h("span", { class: "translation", dir: "auto" }, String(w.translation ?? "")),
      w.category ? h("span", { class: "category", dir: "auto" }, String(w.category)) : null,
      Array.isArray(w.tags) && w.tags.length ? h("span", { class: "tags" }, ...w.tags.map((tag) => h("span", { class: "tag", dir: "auto" }, String(tag)))) : null,
    ),
  );
  return screenFrame(
    { title: tr("Your words", lang), nav, syncedAt, status, freshness, lang, onRefresh, now },
    tr,
    rows.length ? h("ul", { class: "list" }, ...rows) : h("p", { class: "empty" }, tr("No words yet. Add words in the Palabra app on your phone.", lang)),
  );
}

export function removedScreen({ lang, onPairAgain }, tr = t) {
  return h(
    "main",
    { class: "screen", lang },
    h("h1", {}, tr("This computer was removed", lang)),
    h("p", { class: "secondary" }, tr("Pair it again from your phone to keep using Palabra here.", lang)),
    button(tr("Pair again", lang), onPairAgain, { id: "pair-again" }),
  );
}
