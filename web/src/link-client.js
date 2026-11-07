// Phase 1 web client: pair with the phone over the local hop, then ping through the relay.
// No UI framework; link-proof.html drives it. Everything that touches the network takes its `fetch`
// and `WebSocket` as arguments so the Node tests can run the whole flow against fakes.

import { fromHex, toHex, pairingProof, unwrapSecret, roomId, Session, SECRET_BYTES } from "./link-crypto.js";
import { createRpc } from "./link-rpc.js";

export const PAIRING_PORT = 47615;

/** Why the local hop failed, in words a person can act on. `kind` is what the proof page reports back. */
export function explainFetchFailure(error, { isFileOrigin }) {
  const kind = isFileOrigin ? "file-blocked-or-unreachable" : "unreachable";
  return {
    kind,
    message: isFileOrigin
      ? "The browser could not reach the phone. Check that both are on the same Wi-Fi and the phone's Pair a Browser screen is open. If they are, this browser may block pages opened from a file from reaching your network: allow local network access if it asks, or try Chrome or Edge."
      : "Could not reach the phone. Check that both are on the same Wi-Fi and the phone's Pair a Browser screen is open.",
    detail: String(error && error.message ? error.message : error),
  };
}

/** Normalises what the person typed ("192.168.1.20" or "192.168.1.20:47615") into a base URL. */
export function phoneBase(input) {
  const text = String(input || "").trim().replace(/^https?:\/\//, "").replace(/\/+$/, "");
  const m = /^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$/.exec(text);
  if (!m || m[1].split(".").some((n) => Number(n) > 255)) throw new Error("Type the phone's address like 192.168.1.20");
  return `http://${m[1]}:${m[2] ?? PAIRING_PORT}`;
}

/** The pairing hop. Resolves with the session secret, or rejects with {kind, message, ...}. */
export async function pairWithPhone({ address, code, fetchImpl = fetch, isFileOrigin = false }) {
  if (!/^\d{6,}$/.test(code)) throw { kind: "bad-code", message: "The code is at least 6 digits." };
  const base = phoneBase(address);
  let hello;
  try {
    const r = await fetchImpl(`${base}/hello`, { cache: "no-store" });
    if (r.status === 423) {
      const { seconds } = await r.json();
      throw { kind: "locked", seconds, message: `Too many wrong codes. Try again in ${seconds} seconds.` };
    }
    if (!r.ok) throw { kind: "closed", message: "The phone is not accepting a pairing. Open Pair a Browser on the phone." };
    hello = await r.json();
  } catch (e) {
    if (e && e.kind) throw e;
    throw explainFetchFailure(e, { isFileOrigin });
  }
  const nonce = fromHex(hello.nonce);
  const proof = toHex(await pairingProof(code, nonce));
  let reply, body;
  try {
    reply = await fetchImpl(`${base}/pair`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ nonce: hello.nonce, proof }),
    });
    body = await reply.json();
  } catch (e) {
    throw explainFetchFailure(e, { isFileOrigin });
  }
  if (reply.status === 423) throw { kind: "locked", seconds: body.seconds, message: `Too many wrong codes. Try again in ${body.seconds} seconds.` };
  if (!reply.ok) {
    if (body.error === "wrong") throw { kind: "wrong", triesLeft: body.triesLeft, message: `Wrong code. ${body.triesLeft} tries left.` };
    throw { kind: "closed", message: "The phone refused. Open Pair a Browser on the phone and try again." };
  }
  try {
    return await unwrapSecret(code, nonce, fromHex(body.iv), fromHex(body.sealed));
  } catch {
    throw { kind: "bad-reply", message: "The phone's answer could not be opened." };
  }
}

/** The sealed pairing payload is the 32-byte secret, then (from this version of the app) the phone's own relay address. */
export function splitPairing(opened) {
  const bytes = opened instanceof Uint8Array ? opened : new Uint8Array(opened);
  const relay = bytes.length > SECRET_BYTES ? new TextDecoder().decode(bytes.subarray(SECRET_BYTES)).trim() : "";
  return { secret: bytes.slice(0, SECRET_BYTES), relayUrl: relay };
}

/** Pairs, and also returns the relay address the phone is using (empty with an older app). */
export async function pairWithPhoneFull(options) {
  return splitPairing(await pairWithPhone(options));
}

/** Turns what the person typed for the relay into a websocket address. Accepts wss://, ws://, https://, http:// or a bare host. */
export function relayBase(input) {
  const bad = { kind: "relay-address", message: "That relay address does not look right. Use wss://palabra-relay.yourname.workers.dev" };
  let text = String(input || "").trim().replace(/\/+$/, "");
  if (!text) throw { kind: "relay-address", message: "Type the relay address, like wss://palabra-relay.yourname.workers.dev" };
  text = text.replace(/^https:\/\//i, "wss://").replace(/^http:\/\//i, "ws://");
  if (!/^wss?:\/\//i.test(text)) text = `wss://${text}`;
  const m = /^(wss?):\/\/([a-z0-9]([a-z0-9.-]*[a-z0-9])?)(:\d{1,5})?(\/[^\s?#]*)?$/i.exec(text);
  if (!m || (!m[2].includes(".") && m[2].toLowerCase() !== "localhost")) throw bad;
  return `${m[1].toLowerCase()}://${m[2]}${m[4] ?? ""}${(m[5] ?? "").replace(/\/+$/, "")}`;
}

export const HEARTBEAT_MS = 20000;     // how often a quiet link checks the other end is still there
export const SILENCE_MS = 50000;       // nothing heard for this long (not even a heartbeat answer): the socket is dead, reconnect

/**
 * Connects to the relay with the session secret and returns a small object to talk to the phone.
 * It sits in the browser's seat ("web") of the room, so a reconnect always replaces its own earlier, possibly dead, socket.
 * The relay tells it when the phone arrives or leaves (`onPeer`), so it never has to guess by waiting. While connected it
 * checks the other end every HEARTBEAT_MS; if nothing at all is heard for SILENCE_MS the socket is treated as dead and closed,
 * which makes the caller reconnect, instead of sitting on a connection that stopped working.
 */
export async function openLink({ relayUrl, secret, WebSocketImpl = WebSocket, timeoutMs = 15000, connectTimeoutMs = 10000, onClose = () => {}, onPeer = () => {}, setTimer = setTimeout, clearTimer = clearTimeout, setRepeat = setInterval, clearRepeat = clearInterval, nowMs = () => Date.now(), heartbeatMs = HEARTBEAT_MS, silenceMs = SILENCE_MS, tokenHex = null }) {
  const room = await roomId(secret);
  const session = await Session.open(secret, "web");
  const ws = new WebSocketImpl(`${relayBase(relayUrl)}/r/${room}?role=web`);
  ws.binaryType = "arraybuffer";
  const rpc = createRpc({ timeoutMs, send: async (message) => ws.send(await session.seal(message)) });
  let lastHeard = nowMs(), peerHere = null, beat = null, closedByUs = false;      // null: this relay does not report presence (an older one)
  ws.addEventListener("message", async (event) => {
    lastHeard = nowMs();
    if (typeof event.data === "string") {          // the relay's own notices; peers can only send binary
      if (event.data === "peer:here" || event.data === "peer:gone") { peerHere = event.data === "peer:here"; onPeer(peerHere); }
      return;
    }
    try { rpc.receive(await session.open(new Uint8Array(event.data))); }
    catch { /* not for us, tampered or replayed: ignore */ }
  });
  let opened = false;
  const stopBeat = () => { if (beat !== null) { clearRepeat(beat); beat = null; } };
  // A replaced socket (code 4005) means a newer page of ours took the seat; nothing to reconnect.
  ws.addEventListener("close", (event) => { stopBeat(); rpc.failAll("link-lost"); if (opened && !closedByUs && event?.code !== 4005) onClose(); });
  await new Promise((resolve, reject) => {
    const fail = (kind, message) => { clearTimer(timer); try { ws.close(); } catch { /* already closed */ } reject({ kind, message }); };
    const timer = setTimer(() => fail("relay-timeout", "The relay did not answer. Check its address, and that it is deployed."), connectTimeoutMs);
    ws.addEventListener("open", () => { opened = true; clearTimer(timer); resolve(); }, { once: true });
    ws.addEventListener("error", () => fail("relay", "Could not reach the relay. Check its address."), { once: true });
    ws.addEventListener("close", (event) => { if (!opened) fail(event?.code === 4001 ? "room-full" : "relay", event?.code === 4001 ? "Another browser is already linked to this phone. Close it first." : "The relay refused the connection. Check its address."); }, { once: true });
  });
  beat = setRepeat(() => {
    if (nowMs() - lastHeard > silenceMs) { stopBeat(); try { ws.close(); } catch { /* already closed */ } return; }
    if (peerHere !== false) rpc.request("ping", { sentAt: nowMs() }).then(() => { lastHeard = nowMs(); }, () => {});
  }, heartbeatMs);
  // A computer the person chose to trust says who it is before anything else. If the phone no longer trusts it (it was removed
  // from the list) the answer is "revoked", which the caller treats as something only the person can fix: no endless retrying.
  // A phone that does not know "hello" (an older app) answers with a refusal of another kind, which is ignored: the code path
  // never sends one.
  const introduce = async () => {
    if (!tokenHex) return;
    try { await rpc.request("hello", { token: tokenHex }); }
    catch (error) { if (error?.kind === "revoked") { try { ws.close(); } catch { /* already closed */ } throw error; } }
  };
  return {
    /** Tells the phone which trusted computer this is. A no-op for a browser that paired with the code. */
    introduce,
    /** Ask the phone for something: `request("snapshot")` or `request("read", {capability, args})`. */
    request: (type, payload) => rpc.request(type, payload),
    /** Encrypted ping; resolves with the phone's ack, rejects with a LinkRpcError (kind "no-answer") if it stays silent. */
    ping: async () => ({ type: "ack", payload: await rpc.request("ping", { sentAt: Date.now() }) }),
    /** true / false when the relay says whether the phone is in the room right now; null when this relay does not say. */
    get peerHere() { return peerHere; },
    close: () => { closedByUs = true; stopBeat(); ws.close(); },
  };
}
