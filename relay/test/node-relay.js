// A real WebSocket server around the same Room logic as the Worker, for tests only.
import http from "node:http";
import { Room, ROOM_ID_PATTERN } from "../src/room.js";

export async function startRelay() {
  const rooms = new Map();
  const server = http.createServer((req, res) => res.end("palabra relay"));
  const { WebSocketServer } = await import("./ws-shim.js");
  const wss = new WebSocketServer({ noServer: true });
  server.on("upgrade", (req, socket, head) => {
    const m = /^\/r\/([0-9a-f]{32})$/.exec(req.url);
    if (!m || !ROOM_ID_PATTERN.test(m[1])) return socket.destroy();
    wss.handleUpgrade(req, socket, head, (ws) => {
      let room = rooms.get(m[1]);
      if (!room) rooms.set(m[1], (room = new Room()));
      const peer = { send: (d) => ws.send(d), close: (c, r) => ws.close(c, r) };
      if (!room.join(peer)) return;
      ws.on("message", (data, isBinary) => room.message(peer, isBinary ? data : data.toString()));
      ws.on("close", () => room.leave(peer));
    });
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { url: `ws://127.0.0.1:${server.address().port}`, close: () => server.close() };
}
