// The lobby: where a phone and a browser on the same network find each other before they trust each other.
// Pure logic, like room.js. It forwards small JSON text frames to everyone else in the lobby and keeps nothing.
// The lobby is named from the connecting public address, so only devices behind the same router share one.
// Lobby frames are never secrets: a display name, a one-time public key, and an accept or decline.

export const LOBBY_MAX_PEERS = 16;
export const LOBBY_MAX_FRAME_CHARS = 2048;
export const LOBBY_FRAMES_PER_SECOND = 20;
export const LOBBY_CLOSE = {
  full: { code: 4011, reason: "lobby full" },
  tooBig: { code: 4012, reason: "frame too big" },
  tooFast: { code: 4013, reason: "rate limit" },
  notText: { code: 4014, reason: "text frames only" },
  notJson: { code: 4015, reason: "bad frame" },
};
export const LOBBY_TYPES = ["hello", "announce", "gone", "request", "decision"];

/** The lobby name for a public address: a keyed hash, so the address itself is not the name and cannot be guessed back. */
export async function lobbyName(address, salt) {
  const data = new TextEncoder().encode(`palabra-lobby-v1|${salt}|${String(address || "unknown")}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(digest.subarray(0, 16), (b) => b.toString(16).padStart(2, "0")).join("");
}

export class Lobby {
  constructor(now = () => Date.now()) {
    this.peers = new Map();   // peer -> { tokens, last }
    this.now = now;
  }

  join(peer) {
    if (this.peers.size >= LOBBY_MAX_PEERS) { peer.close(LOBBY_CLOSE.full.code, LOBBY_CLOSE.full.reason); return false; }
    this.peers.set(peer, { tokens: LOBBY_FRAMES_PER_SECOND * 2, last: this.now() });
    return true;
  }

  leave(peer) { this.peers.delete(peer); }

  #take(state) {
    const t = this.now();
    state.tokens = Math.min(LOBBY_FRAMES_PER_SECOND * 2, state.tokens + ((t - state.last) / 1000) * LOBBY_FRAMES_PER_SECOND);
    state.last = t;
    if (state.tokens < 1) return false;
    state.tokens -= 1;
    return true;
  }

  /** Passes one text frame to everyone else. Anything that is not a small JSON object of a known type closes the sender. */
  message(from, data) {
    const state = this.peers.get(from);
    if (!state) return;
    if (typeof data !== "string") return from.close(LOBBY_CLOSE.notText.code, LOBBY_CLOSE.notText.reason);
    if (data.length > LOBBY_MAX_FRAME_CHARS) return from.close(LOBBY_CLOSE.tooBig.code, LOBBY_CLOSE.tooBig.reason);
    if (!this.#take(state)) return from.close(LOBBY_CLOSE.tooFast.code, LOBBY_CLOSE.tooFast.reason);
    let parsed;
    try { parsed = JSON.parse(data); } catch { return from.close(LOBBY_CLOSE.notJson.code, LOBBY_CLOSE.notJson.reason); }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || !LOBBY_TYPES.includes(parsed.type)) {
      return from.close(LOBBY_CLOSE.notJson.code, LOBBY_CLOSE.notJson.reason);
    }
    for (const peer of this.peers.keys()) if (peer !== from) peer.send(data);
  }

  get size() { return this.peers.size; }
}
