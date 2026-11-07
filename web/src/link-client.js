// Phase 1 web client: pair with the phone over the local hop, then ping through the relay.
// No UI framework; link-proof.html drives it. Everything that touches the network takes its `fetch`
// and `WebSocket` as arguments so the Node tests can run the whole flow against fakes.

import { fromHex, toHex, pairingProof, unwrapSecret, roomId, Session } from "./link-crypto.js";
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

/** Connects to the relay with the session secret and returns a small object to send pings. */
export async function openLink({ relayUrl, secret, WebSocketImpl = WebSocket, timeoutMs = 15000, onClose = () => {} }) {
  const room = await roomId(secret);
  const session = await Session.open(secret, "web");
  const ws = new WebSocketImpl(`${relayUrl.replace(/\/+$/, "")}/r/${room}`);
  ws.binaryType = "arraybuffer";
  const rpc = createRpc({ timeoutMs, send: async (message) => ws.send(await session.seal(message)) });
  ws.addEventListener("message", async (event) => {
    try { rpc.receive(await session.open(new Uint8Array(event.data))); }
    catch { /* not for us, tampered or replayed: ignore */ }
  });
  ws.addEventListener("close", () => { rpc.failAll("link-lost"); onClose(); });
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", () => reject({ kind: "relay", message: "Could not reach the relay. Check its address." }), { once: true });
  });
  return {
    /** Ask the phone for something: `request("snapshot")` or `request("read", {capability, args})`. */
    request: (type, payload) => rpc.request(type, payload),
    /** Encrypted ping; resolves with the phone's ack, rejects with a LinkRpcError (kind "no-answer") if it stays silent. */
    ping: async () => ({ type: "ack", payload: await rpc.request("ping", { sentAt: Date.now() }) }),
    close: () => ws.close(),
  };
}
