// Palabra web link, phase 1: the crypto both ends must agree on byte for byte.
// Protocol v1, see docs/superpowers/specs/2026-11-07-web-companion-phase1.md.
// Uses only WebCrypto (crypto.subtle), which browsers and Node 20+ both provide.

const enc = new TextEncoder();
const dec = new TextDecoder();

export const PROTOCOL = "palabra-link-v1";
export const SECRET_BYTES = 32;

export function toHex(bytes) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function fromHex(hex) {
  if (typeof hex !== "string" || hex.length % 2 !== 0 || /[^0-9a-f]/i.test(hex)) throw new Error("bad hex");
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function randomBytes(n) {
  return crypto.getRandomValues(new Uint8Array(n));
}

async function hkdf(ikm, salt, info, bytes) {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt, info: enc.encode(info) },
    key,
    bytes * 8,
  );
  return new Uint8Array(bits);
}

// ---- pairing (over the local hop only) -------------------------------------

/** Proof that the page knows the code, without sending the code. */
export async function pairingProof(code, nonce) {
  const k = await hkdf(enc.encode(code), nonce, "palabra-proof-v1", 32);
  const hmacKey = await crypto.subtle.importKey("raw", k, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", hmacKey, nonce));
}

async function wrapKey(code, nonce) {
  const k = await hkdf(enc.encode(code), nonce, "palabra-wrap-v1", 32);
  return crypto.subtle.importKey("raw", k, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** App side (also used by tests): seal the session secret so only someone who knows the code can open it. */
export async function wrapSecret(code, nonce, secret, iv = randomBytes(12)) {
  const ct = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: nonce }, await wrapKey(code, nonce), secret),
  );
  return { iv, ct };
}

/** Page side: open the wrapped secret with the code. Throws if the code is wrong. */
export async function unwrapSecret(code, nonce, iv, ct) {
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv, additionalData: nonce }, await wrapKey(code, nonce), ct);
  return new Uint8Array(pt);
}

// ---- session (over the relay) ----------------------------------------------

/** The relay room id. Derived from the secret, so the relay learns neither the code nor the secret. */
export async function roomId(secret) {
  return toHex(await hkdf(secret, new Uint8Array(0), "palabra-room-v1", 16));
}

/** Direction bytes: which end sent a frame. Bound into the AEAD so a frame can't be reflected back. */
export const DIR = { app: 0x41, web: 0x57 };

export class Session {
  /** @param {Uint8Array} secret  @param {"app"|"web"} role */
  constructor(key, role) {
    this.key = key;
    this.role = role;
    this.epoch = randomBytes(8);          // this end's stream id: a rebuilt session is a new stream, not a replay of the old one
    this.sendCounter = 0;
    this.peerEpoch = null;                // hex of the stream we are currently listening to
    this.lastReceived = -1;
    this.leftEpochs = new Set();          // streams we moved on from: a frame from one of them is an old replay
    this.queue = Promise.resolve();       // frames are checked one at a time, in arrival order (decrypting is asynchronous)
  }

  static async open(secret, role) {
    const raw = await hkdf(secret, new Uint8Array(0), "palabra-aead-v2", 32);
    const key = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
    return new Session(key, role);
  }

  /** Frame layout: iv(12) | epoch(8) | counter(8, big endian) | ciphertext+tag. Direction, epoch and counter are all authenticated. */
  async seal(message) {
    const iv = randomBytes(12);
    const counter = this.sendCounter++;
    const aad = frameAad(DIR[this.role], this.epoch, counter);
    const ct = new Uint8Array(
      await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: aad }, this.key, enc.encode(JSON.stringify(message))),
    );
    const out = new Uint8Array(12 + 16 + ct.length);
    out.set(iv, 0);
    out.set(aad.subarray(1), 12);
    out.set(ct, 28);
    return out;
  }

  /** Opens a frame from the other end. Rejects tampering, reflection and replays. A new epoch is a reconnected peer, not a replay. */
  open(frame) {
    const turn = this.queue.then(() => this.#open(frame));
    this.queue = turn.catch(() => {});     // one bad frame never blocks the ones behind it
    return turn;
  }

  async #open(frame) {
    if (!(frame instanceof Uint8Array) || frame.length < 12 + 16 + 16) throw new Error("short frame");
    const peer = this.role === "app" ? DIR.web : DIR.app;
    const iv = frame.subarray(0, 12);
    const epoch = frame.slice(12, 20);
    const counterBytes = frame.slice(20, 28);
    const counter = Number(new DataView(counterBytes.buffer, counterBytes.byteOffset, 8).getBigUint64(0));
    const aad = frameAad(peer, epoch, counter);
    let pt;
    try {
      pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv, additionalData: aad }, this.key, frame.subarray(28));
    } catch {
      throw new Error("bad frame");
    }
    const id = toHex(epoch);
    if (id !== this.peerEpoch) {
      if (this.leftEpochs.has(id)) throw new Error("replayed frame");          // an earlier stream, played back
      if (this.peerEpoch !== null) this.leftEpochs.add(this.peerEpoch);
      if (this.leftEpochs.size > 64) this.leftEpochs.delete(this.leftEpochs.values().next().value);
      this.peerEpoch = id;
      this.lastReceived = -1;
    }
    if (counter <= this.lastReceived) throw new Error("replayed frame");
    this.lastReceived = counter;
    return JSON.parse(dec.decode(pt));
  }
}

function frameAad(dir, epoch, counter) {
  const aad = new Uint8Array(17);
  aad[0] = dir;
  aad.set(epoch, 1);
  new DataView(aad.buffer).setBigUint64(9, BigInt(counter));
  return aad;
}
