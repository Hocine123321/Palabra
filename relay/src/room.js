// The relay's whole job, as pure logic: a room holds at most two sockets and forwards every
// binary frame from one to the other. It never parses, stores or logs a frame.
// Used by the Durable Object (worker.js) and by the Node test server (test/node-relay.js).

export const MAX_FRAME_BYTES = 256 * 1024;      // snapshots are chunked below this
export const MAX_PEERS = 2;
export const MAX_FRAMES_PER_SECOND = 50;        // per socket; a burst of 2x is tolerated
export const ROOM_ID_PATTERN = /^[0-9a-f]{32}$/;

export const ROLES = ["app", "web"];
export const CLOSE = {
  roomFull: { code: 4001, reason: "room full" },
  replaced: { code: 4005, reason: "replaced by a newer connection" },
  tooBig: { code: 4002, reason: "frame too big" },
  tooFast: { code: 4003, reason: "rate limit" },
  notBinary: { code: 4004, reason: "binary frames only" },
};

/** A tiny token bucket so one socket cannot flood the other end. */
export class Bucket {
  constructor(perSecond = MAX_FRAMES_PER_SECOND, now = () => Date.now()) {
    this.capacity = perSecond * 2;
    this.perSecond = perSecond;
    this.tokens = this.capacity;
    this.now = now;
    this.last = now();
  }
  take() {
    const t = this.now();
    this.tokens = Math.min(this.capacity, this.tokens + ((t - this.last) / 1000) * this.perSecond);
    this.last = t;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

/**
 * @typedef {{send(data: ArrayBuffer|Uint8Array|string): void, close(code: number, reason: string): void}} Peer
 *
 * A room has one seat per role: the phone ("app") and the browser ("web"). A new connection in a role REPLACES the old one in that
 * role, so a socket that died without the relay noticing can never lock out the connection that follows it. The room id is
 * derived from a 32-byte secret, so only someone who holds the secret can sit in a seat, and frames are end-to-end encrypted anyway.
 * The relay also tells each end, in text frames of its own, whether the other seat is taken: "peer:here" or "peer:gone".
 * Peers may only send binary frames, so nobody can forge those notices.
 */
export class Room {
  constructor(now = () => Date.now()) {
    /** @type {Map<Peer, Bucket>} */
    this.peers = new Map();
    /** @type {Map<string, Peer>} */
    this.seats = new Map();
    this.now = now;
  }

  /** Seats a peer in a role. An unknown role is refused. Returns false (and closes the peer) when it cannot be seated. */
  join(peer, role = null) {
    if (role === null) {
      // Older clients do not name a role: first come, first served, as before.
      if (this.peers.size >= MAX_PEERS) { peer.close(CLOSE.roomFull.code, CLOSE.roomFull.reason); return false; }
      this.peers.set(peer, new Bucket(MAX_FRAMES_PER_SECOND, this.now));
      return true;
    }
    if (!ROLES.includes(role)) { peer.close(CLOSE.roomFull.code, CLOSE.roomFull.reason); return false; }
    const old = this.seats.get(role);
    if (old) {
      this.seats.delete(role);
      this.peers.delete(old);
      try { old.close(CLOSE.replaced.code, CLOSE.replaced.reason); } catch { /* already gone */ }
    }
    this.seats.set(role, peer);
    this.peers.set(peer, new Bucket(MAX_FRAMES_PER_SECOND, this.now));
    peer.role = role;
    this.#tell(peer, this.#otherSeated(role) ? "peer:here" : "peer:gone");
    this.#tellOthers(peer, "peer:here");
    return true;
  }

  leave(peer) {
    if (!this.peers.delete(peer)) return;
    const role = [...this.seats].find(([, p]) => p === peer)?.[0];
    if (role) {
      this.seats.delete(role);
      this.#tellOthers(peer, "peer:gone");
    }
  }

  #otherSeated(role) { return this.seats.has(role === "app" ? "web" : "app"); }

  #tell(peer, text) { try { peer.send(text); } catch { /* the socket is already closing */ } }

  #tellOthers(from, text) {
    for (const p of this.peers.keys()) if (p !== from) this.#tell(p, text);
  }

  /** Forward one frame to the other end. Anything that is not a small binary frame closes the sender. */
  message(from, data) {
    const bucket = this.peers.get(from);
    if (!bucket) return;
    if (typeof data === "string") return from.close(CLOSE.notBinary.code, CLOSE.notBinary.reason);
    const size = data.byteLength ?? data.length;
    if (size > MAX_FRAME_BYTES) return from.close(CLOSE.tooBig.code, CLOSE.tooBig.reason);
    if (!bucket.take()) return from.close(CLOSE.tooFast.code, CLOSE.tooFast.reason);
    for (const peer of this.peers.keys()) if (peer !== from) peer.send(data);
  }

  get size() {
    return this.peers.size;
  }
}
