// The relay's whole job, as pure logic: a room holds at most two sockets and forwards every
// binary frame from one to the other. It never parses, stores or logs a frame.
// Used by the Durable Object (worker.js) and by the Node test server (test/node-relay.js).

export const MAX_FRAME_BYTES = 256 * 1024;      // snapshots are chunked below this
export const MAX_PEERS = 2;
export const MAX_FRAMES_PER_SECOND = 50;        // per socket; a burst of 2x is tolerated
export const ROOM_ID_PATTERN = /^[0-9a-f]{32}$/;

export const CLOSE = {
  roomFull: { code: 4001, reason: "room full" },
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
 * @typedef {{send(data: ArrayBuffer|Uint8Array): void, close(code: number, reason: string): void}} Peer
 */
export class Room {
  constructor(now = () => Date.now()) {
    /** @type {Map<Peer, Bucket>} */
    this.peers = new Map();
    this.now = now;
  }

  /** Returns false (and closes the peer) when the room already has two ends. */
  join(peer) {
    if (this.peers.size >= MAX_PEERS) {
      peer.close(CLOSE.roomFull.code, CLOSE.roomFull.reason);
      return false;
    }
    this.peers.set(peer, new Bucket(MAX_FRAMES_PER_SECOND, this.now));
    return true;
  }

  leave(peer) {
    this.peers.delete(peer);
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
