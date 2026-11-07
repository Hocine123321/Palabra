// A real WebSocket server around the same Room logic as the Worker, for tests only.
import http from "node:http";
import { Room, ROOM_ID_PATTERN, ROLES } from "../src/room.js";
import { Lobby, lobbyName } from "../src/lobby.js";

export async function startRelay() {
  const rooms = new Map();
  const lobbies = new Map();
  const server = http.createServer((req, res) => res.end("palabra relay"));
  const { WebSocketServer } = await import("./ws-shim.js");
  const wss = new WebSocketServer({ noServer: true });
  server.on("upgrade", async (req, socket, head) => {
    if (req.url === "/lobby") {
      // The test server has no CF header: a test may name an address with x-test-ip, to stand for a router.
      const name = await lobbyName(req.headers["x-test-ip"] || req.socket.remoteAddress, "palabra");
      return wss.handleUpgrade(req, socket, head, (ws) => {
        let lobby = lobbies.get(name);
        if (!lobby) lobbies.set(name, (lobby = new Lobby()));
        const peer = { send: (d) => ws.send(d), close: (c, r) => ws.close(c, r) };
        if (!lobby.join(peer)) return;
        ws.on("message", (data, isBinary) => lobby.message(peer, isBinary ? data : data.toString()));
        ws.on("close", () => lobby.leave(peer));
      });
    }
    const parsed = new URL(req.url, "http://relay");
    const role = parsed.searchParams.get("role");
    if (role !== null && !ROLES.includes(role)) return socket.destroy();
    const m = /^\/r\/([0-9a-f]{32})$/.exec(parsed.pathname);
    if (!m || !ROOM_ID_PATTERN.test(m[1])) return socket.destroy();
    wss.handleUpgrade(req, socket, head, (ws) => {
      let room = rooms.get(m[1]);
      if (!room) rooms.set(m[1], (room = new Room()));
      const peer = { send: (d) => ws.send(d), close: (c, r) => ws.close(c, r) };
      if (!room.join(peer, role)) return;
      ws.on("message", (data, isBinary) => room.message(peer, isBinary ? data : data.toString()));
      ws.on("close", () => room.leave(peer));
    });
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { url: `ws://127.0.0.1:${server.address().port}`, close: () => server.close() };
}
