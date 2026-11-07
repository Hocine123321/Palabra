// Automatic pairing, page side: find phones through the relay's lobby, ask one to trust this computer, and open what it grants.
// No DOM here and the socket is injected, so every step can be tested. Protocol: docs/superpowers/specs/2026-11-07-web-companion-phase6-auto-pair.md.
// The lobby only introduces devices. Nothing is trusted until the person taps Trust on the phone, and the four digits on both screens
// prove neither public key was swapped on the way.

import { makeTrustKeys, matchCode, openGrant } from "./trust-crypto.js";
import { relayBase } from "./link-client.js";
import { toHex, randomBytes } from "./link-crypto.js";

export const FIND_MS = 4000;          // how long the search listens for phones before saying "none found"
export const ANSWER_MS = 65000;       // the phone's popup times out after 60 s
export const MAX_PHONES = 8;
const lobbyClip = (v, n) => String(v ?? "").slice(0, n);
const lobbyIsHex = (v, n) => typeof v === "string" && v.length === n && /^[0-9a-f]+$/i.test(v);

/** A short name for this computer, shown on the phone's popup. Never anything personal beyond what the browser reports. */
export function computerName(nav = globalThis.navigator) {
  const ua = String(nav?.userAgent ?? "");
  const os = /Windows/i.test(ua) ? "Windows" : /Mac OS X|Macintosh/i.test(ua) ? "Mac" : /Linux/i.test(ua) ? "Linux" : /CrOS/i.test(ua) ? "Chromebook" : "Computer";
  const browser = /Edg\//.test(ua) ? "Edge" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : "Browser";
  return `${browser} on ${os}`;
}

function openLobbySocket({ relayUrl, WebSocketImpl, setTimer, clearTimer, connectMs = 10000 }) {
  const ws = new WebSocketImpl(`${relayBase(relayUrl)}/lobby`);
  const listeners = new Set();
  ws.addEventListener("message", (event) => {
    if (typeof event.data !== "string" || event.data.length > 2048) return;
    let frame;
    try { frame = JSON.parse(event.data); } catch { return; }
    if (frame && typeof frame === "object" && !Array.isArray(frame)) for (const l of [...listeners]) l(frame);
  });
  const ready = new Promise((resolve, reject) => {
    const timer = setTimer(() => { try { ws.close(); } catch { /* closed */ } reject({ kind: "relay-timeout", message: "The relay did not answer. Check its address, and that it is deployed." }); }, connectMs);
    ws.addEventListener("open", () => { clearTimer(timer); resolve(); }, { once: true });
    ws.addEventListener("error", () => { clearTimer(timer); reject({ kind: "relay", message: "Could not reach the relay. Check its address." }); }, { once: true });
    ws.addEventListener("close", () => { clearTimer(timer); reject({ kind: "relay", message: "The relay refused the connection. Check its address." }); }, { once: true });
  });
  return {
    ready,
    send: (frame) => ws.send(JSON.stringify(frame)),
    on: (fn) => { listeners.add(fn); return () => listeners.delete(fn); },
    close: () => { try { ws.close(); } catch { /* closed */ } },
  };
}

/** Phones in the lobby that announced themselves. Resolves after FIND_MS with the list, newest announcement winning per phone. */
export async function findPhones({ relayUrl, WebSocketImpl = WebSocket, setTimer = setTimeout, clearTimer = clearTimeout, findMs = FIND_MS, onPhone = () => {} }) {
  const lobby = openLobbySocket({ relayUrl, WebSocketImpl, setTimer, clearTimer });
  try {
    await lobby.ready;
    const phones = new Map();
    lobby.on((f) => {
      if (f.type === "gone" && lobbyIsHex(f.deviceId, 32)) { phones.delete(f.deviceId); onPhone([...phones.values()]); return; }
      if (f.type !== "announce" || !lobbyIsHex(f.deviceId, 32) || !lobbyIsHex(f.pub, 130)) return;
      if (!phones.has(f.deviceId) && phones.size >= MAX_PHONES) return;
      phones.set(f.deviceId, { deviceId: f.deviceId, name: lobbyClip(f.name, 40) || "Palabra phone", pub: f.pub.toLowerCase() });
      onPhone([...phones.values()]);
    });
    lobby.send({ type: "hello" });                     // phones answer with an announcement straight away
    await new Promise((r) => setTimer(r, findMs));
    return [...phones.values()];
  } finally { lobby.close(); }
}

/**
 * Asks one phone to trust this computer. `onCode` receives the four digits as soon as they are known so the page can show them
 * while the person decides on the phone. Resolves with { secret, token, relayUrl, deviceId } or rejects with {kind, message}.
 */
export async function requestTrust({ relayUrl, phone, name = computerName(), WebSocketImpl = WebSocket, setTimer = setTimeout, clearTimer = clearTimeout, answerMs = ANSWER_MS, onCode = () => {} }) {
  const lobby = openLobbySocket({ relayUrl, WebSocketImpl, setTimer, clearTimer });
  try {
    await lobby.ready;
    const keys = await makeTrustKeys();
    const browserId = toHex(randomBytes(16));
    onCode(await matchCode(phone.pub, keys.pub));
    const decision = new Promise((resolve, reject) => {
      const timer = setTimer(() => reject({ kind: "no-answer", message: "The phone did not answer. Open Palabra on the phone and try again." }), answerMs);
      lobby.on((f) => {
        if (f.type !== "decision" || f.browserId !== browserId || f.deviceId !== phone.deviceId) return;
        clearTimer(timer);
        if (f.accepted !== true) return reject({ kind: "declined", message: "The phone did not trust this computer." });
        resolve(f);
      });
    });
    lobby.send({ type: "request", to: phone.deviceId, browserId, name: lobbyClip(name, 40), pub: keys.pub });
    const f = await decision;
    let grant;
    try {
      grant = await openGrant({ browserPrivate: keys.privateKey, phonePub: phone.pub, browserPub: keys.pub, iv: f.iv, sealed: f.sealed });
    } catch {
      throw { kind: "bad-grant", message: "The phone's answer could not be verified. Nothing was saved." };
    }
    return { secret: grant.secret, token: grant.token, relayUrl: grant.relayUrl, deviceId: phone.deviceId };
  } finally { lobby.close(); }
}

/** The "Find my phone" panel as markup. Every string goes through the escaper; the phone's name is untrusted text. */
export function renderFinder(finder, t, esc) {
  const row = (p) => `<li><button type="button" class="open" data-phone="${esc(p.deviceId)}"><span class="name">${esc(p.name)}</span></button></li>`;
  switch (finder.state) {
    case "searching": return `<p class="muted">${t("Looking for your phone…")}</p>`;
    case "none": return `<p class="muted">${t("No phone found. Open Settings, Web Access, Pair a Browser on the phone, on the same Wi-Fi as this computer.")}</p>`;
    case "list": return `<ul class="artifacts">${finder.phones.map(row).join("")}</ul>`;
    case "waiting": return `<div class="match"><p>${t("Check your phone and tap Trust.")}</p><p class="code" aria-live="polite">${esc(finder.code)}</p><p class="muted small">${t("Only accept if the phone shows this same number.")}</p></div>`;
    case "error": return `<p class="err" role="alert">${esc(finder.message)}</p>`;
    default: return "";
  }
}
