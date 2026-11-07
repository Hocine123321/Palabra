// A stand-in for the phone: the same HTTP contract as PairingHTTP.swift / PairingService.swift, and an app-side
// Session that answers ping with ack through the relay. Lets the web client be tested end to end without a device.
import http from "node:http";
import { WebSocket } from "ws";
import { randomBytes, toHex, fromHex, pairingProof, wrapSecret, roomId, Session } from "../../web/src/link-crypto.js";

const DURATIONS = [30, 120, 600, 3600];

// Mirrors WebLinkDispatcher.swift: read-only allow-list, all-or-nothing snapshot, chunking above 120 KB.
const ALLOW = new Set(["library.words", "library.word", "study.decks", "review.list", "stats.wordsPerDay", "stats.wordsPerWeek"]);
const SNAPSHOT = { words: "library.words", decks: "study.decks", review: "review.list", wordsPerDay: "stats.wordsPerDay", wordsPerWeek: "stats.wordsPerWeek" };
const PIECE = 120000;

function chunked(reply) {
  const whole = Buffer.from(JSON.stringify(reply));
  if (whole.length <= PIECE) return [reply];
  const total = Math.ceil(whole.length / PIECE);
  return Array.from({ length: total }, (_, index) => ({ id: reply.id, type: "chunk", version: 1,
    payload: { index, total, data: whole.subarray(index * PIECE, (index + 1) * PIECE).toString("base64") } }));
}

export async function startFakePhone({ code, relayUrl, now = () => Date.now(), data = {}, writes = [] }) {
  const reject = (m, reason) => ({ id: m.id, type: "reject", version: 1, payload: { reason } });
  const answer = (m) => {
    if (m.type === "ping") return { id: m.id, type: "ack", version: 1, payload: m.payload };
    if (m.type === "read") {
      const name = m.payload?.capability;
      if (typeof name !== "string") return reject(m, "bad-request");
      if (!ALLOW.has(name)) { writes.push(name); return reject(m, "forbidden"); }
      return { id: m.id, type: "ack", version: 1, payload: { result: data[name] ?? [] } };
    }
    if (m.type === "snapshot") {
      const snapshot = {}; for (const [key, cap] of Object.entries(SNAPSHOT)) snapshot[key] = data[cap] ?? [];
      return { id: m.id, type: "ack", version: 1, payload: { snapshot, takenAt: new Date(now()).toISOString() } };
    }
    return null;
  };
  const secret = randomBytes(32);
  const nonces = new Map();
  let wrong = 0, lockouts = 0, lockedUntil = 0, paired = false;
  const answered = [];

  const server = http.createServer(async (req, res) => {
    const cors = { "access-control-allow-origin": req.headers.origin ?? "*", "access-control-allow-private-network": "true",
      "access-control-allow-headers": "content-type", "access-control-allow-methods": "GET, POST, OPTIONS" };
    const send = (status, json) => { res.writeHead(status, { ...cors, "content-type": "application/json" }); res.end(json ? JSON.stringify(json) : ""); };
    if (req.method === "OPTIONS") return send(204);
    if (req.method === "GET" && req.url === "/hello") {
      if (now() < lockedUntil) return send(423, { error: "locked", seconds: Math.ceil((lockedUntil - now()) / 1000) });
      const nonce = randomBytes(16); nonces.set(toHex(nonce), now());
      return send(200, { protocol: "palabra-link-v1", nonce: toHex(nonce) });
    }
    if (req.method === "POST" && req.url === "/pair") {
      let raw = ""; for await (const c of req) raw += c;
      const { nonce, proof } = JSON.parse(raw);
      if (now() < lockedUntil) return send(423, { error: "locked", seconds: Math.ceil((lockedUntil - now()) / 1000) });
      if (!nonces.delete(nonce)) return send(400, { error: "bad request" });
      const expected = toHex(await pairingProof(code, fromHex(nonce)));
      if (proof === expected) {
        const { iv, ct } = await wrapSecret(code, fromHex(nonce), secret);
        paired = true; wrong = 0; lockouts = 0;
        return send(200, { iv: toHex(iv), sealed: toHex(ct) });
      }
      if (++wrong >= 5) { const len = DURATIONS[Math.min(lockouts++, 3)]; wrong = 0; lockedUntil = now() + len * 1000; return send(423, { error: "locked", seconds: len }); }
      return send(400, { error: "wrong", triesLeft: 5 - wrong });
    }
    send(404);
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));

  // The app's relay side: answer ping with ack.
  const room = await roomId(secret);
  const app = await Session.open(secret, "app");
  const ws = new WebSocket(`${relayUrl}/r/${room}`);
  ws.binaryType = "nodebuffer";
  ws.on("message", async (d) => {
    try {
      const m = await app.open(new Uint8Array(d)); answered.push(m);
      const reply = answer(m);
      if (reply) for (const piece of chunked(reply)) ws.send(await app.seal(piece));
    } catch {}
  });
  await new Promise((r) => ws.on("open", r));
  return { port: server.address().port, secret, answered, isPaired: () => paired, close: () => { ws.close(); server.close(); } };
}
