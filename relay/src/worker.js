// Cloudflare Worker + Durable Object: GET /r/<room id> with an Upgrade header joins that room.
// The room id is derived from the session secret on both ends (see link-crypto.js), so the relay
// never sees the pairing code or the secret. Nothing is stored: the Durable Object keeps only the
// two open sockets in memory, and uses WebSocket hibernation so an idle room costs nothing.

import { Room, ROOM_ID_PATTERN } from "./room.js";

export class RelayRoom {
  constructor(state) {
    this.state = state;
    this.room = new Room();
    this.byWs = new Map();
    // After hibernation the sockets survive but this object is new: re-adopt them.
    for (const ws of state.getWebSockets()) this.adopt(ws);
  }

  adopt(ws) {
    const peer = { send: (d) => ws.send(d), close: (c, r) => ws.close(c, r) };
    this.byWs.set(ws, peer);
    this.room.join(peer);
    return peer;
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.state.acceptWebSocket(server);
    this.adopt(server); // a third socket is closed by Room.join
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, data) {
    const peer = this.byWs.get(ws);
    if (peer) this.room.message(peer, data);
  }

  webSocketClose(ws) {
    const peer = this.byWs.get(ws);
    if (peer) this.room.leave(peer);
    this.byWs.delete(ws);
  }

  webSocketError(ws) {
    this.webSocketClose(ws);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = /^\/r\/([0-9a-f]{32})$/.exec(url.pathname);
    if (url.pathname === "/") return new Response("palabra relay", { status: 200 });
    if (!match || !ROOM_ID_PATTERN.test(match[1])) return new Response("not found", { status: 404 });
    const id = env.ROOMS.idFromName(match[1]);
    return env.ROOMS.get(id).fetch(request);
  },
};
