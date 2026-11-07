// Cloudflare Worker + Durable Object: GET /r/<room id> with an Upgrade header joins that room.
// The room id is derived from the session secret on both ends (see link-crypto.js), so the relay
// never sees the pairing code or the secret. Nothing is stored: the Durable Object keeps only the
// two open sockets in memory, and uses WebSocket hibernation so an idle room costs nothing.

import { Room, ROOM_ID_PATTERN, ROLES } from "./room.js";
import { Lobby, lobbyName } from "./lobby.js";

export class RelayRoom {
  constructor(state) {
    this.state = state;
    this.room = new Room();
    this.byWs = new Map();
    // After hibernation the sockets survive but this object is new: re-adopt them, each into the seat it had.
    for (const ws of state.getWebSockets()) this.adopt(ws, ws.deserializeAttachment()?.role ?? null);
  }

  adopt(ws, role) {
    const peer = { send: (d) => ws.send(d), close: (c, r) => ws.close(c, r) };
    this.byWs.set(ws, peer);
    this.room.join(peer, role);
    return peer;
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
    // ?role=app (the phone) or ?role=web (the browser). A new connection replaces the old one in its seat.
    const role = new URL(request.url).searchParams.get("role");
    if (role !== null && !ROLES.includes(role)) return new Response("bad role", { status: 400 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ role });          // survives hibernation
    this.adopt(server, role);
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

/** Where devices on one network find each other. Text frames, no storage; the name comes from the caller's public address. */
export class RelayLobby {
  constructor(state) {
    this.state = state;
    this.lobby = new Lobby();
    this.byWs = new Map();
    for (const ws of state.getWebSockets()) this.adopt(ws);
  }

  adopt(ws) {
    const peer = { send: (d) => ws.send(d), close: (c, r) => ws.close(c, r) };
    this.byWs.set(ws, peer);
    this.lobby.join(peer);
    return peer;
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.state.acceptWebSocket(server);
    this.adopt(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, data) {
    const peer = this.byWs.get(ws);
    if (peer) this.lobby.message(peer, data);
  }

  webSocketClose(ws) {
    const peer = this.byWs.get(ws);
    if (peer) this.lobby.leave(peer);
    this.byWs.delete(ws);
  }

  webSocketError(ws) { this.webSocketClose(ws); }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = /^\/r\/([0-9a-f]{32})$/.exec(url.pathname);
    if (url.pathname === "/") return new Response("palabra relay", { status: 200 });
    if (url.pathname === "/lobby") {
      // Same public address, same lobby. The salt is the Worker's own secret if set, so names cannot be computed from outside.
      const name = await lobbyName(request.headers.get("CF-Connecting-IP"), env.LOBBY_SALT || "palabra");
      return env.LOBBIES.get(env.LOBBIES.idFromName(name)).fetch(request);
    }
    if (!match || !ROOM_ID_PATTERN.test(match[1])) return new Response("not found", { status: 404 });
    const id = env.ROOMS.idFromName(match[1]);
    return env.ROOMS.get(id).fetch(request);
  },
};
