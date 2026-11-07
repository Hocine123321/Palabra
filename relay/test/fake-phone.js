// A stand-in for the phone: the same HTTP contract as PairingHTTP.swift / PairingService.swift, and an app-side
// Session that answers ping with ack through the relay. Lets the web client be tested end to end without a device.
import http from "node:http";
import { WebSocket } from "ws";
import { randomBytes, toHex, fromHex, pairingProof, wrapSecret, roomId, Session } from "../../web/src/link-crypto.js";

const DURATIONS = [30, 120, 600, 3600];

export async function startFakePhone({ code, relayUrl, now = () => Date.now() }) {
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
    try { const m = await app.open(new Uint8Array(d)); answered.push(m); if (m.type === "ping") ws.send(await app.seal({ id: m.id, type: "ack", version: 1, payload: m.payload })); } catch {}
  });
  await new Promise((r) => ws.on("open", r));
  return { port: server.address().port, secret, answered, isPaired: () => paired, close: () => { ws.close(); server.close(); } };
}
