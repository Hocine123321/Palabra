// Protocol v1 crypto (docs/features/mirroring.md). WebCrypto only; keys are non-extractable.
import { decode, encode } from "./b64url.js";

export class CryptoFailure extends Error {
  constructor(message = "crypto failure") {
    super(message);
    this.name = "CryptoFailure";
  }
}

const subtle = globalThis.crypto.subtle;
const utf8 = (s) => new TextEncoder().encode(s);
const EMPTY = new Uint8Array(0);
const IV_BYTES = 12;
const TAG_BYTES = 16;

function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

async function wrapErrors(promise) {
  try {
    return await promise;
  } catch (e) {
    throw e instanceof CryptoFailure ? e : new CryptoFailure();
  }
}

/** The two keys derived from the 32-byte data key: kAes (seal/open) and kId (item ids). */
export function importDataKey(raw) {
  return wrapErrors(
    (async () => {
      if (!(raw instanceof Uint8Array) || raw.length !== 32) throw new CryptoFailure("data key must be 32 bytes");
      const base = await subtle.importKey("raw", raw, "HKDF", false, ["deriveKey"]);
      const derive = (info, algorithm, usages) =>
        subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt: EMPTY, info: utf8(info) }, base, algorithm, false, usages);
      return {
        aes: await derive("palabra-mirror-aes-v1", { name: "AES-GCM", length: 256 }, ["encrypt", "decrypt"]),
        id: await derive("palabra-mirror-id-key-v1", { name: "HMAC", hash: "SHA-256", length: 256 }, ["sign"]),
      };
    })(),
  );
}

export function deriveItemId(keys, kind, recordId) {
  return wrapErrors(
    (async () => {
      const mac = new Uint8Array(await subtle.sign("HMAC", keys.id, utf8(`${kind}|${recordId}`)));
      return encode(mac.slice(0, 16));
    })(),
  );
}

export function sealItem(keys, itemId, plaintext, iv = globalThis.crypto.getRandomValues(new Uint8Array(IV_BYTES))) {
  return wrapErrors(
    (async () => {
      const ct = new Uint8Array(
        await subtle.encrypt({ name: "AES-GCM", iv, additionalData: utf8(`palabra-mirror-item-v1|${itemId}`), tagLength: 128 }, keys.aes, plaintext),
      );
      return concat(iv, ct);
    })(),
  );
}

export function openItem(keys, itemId, sealed) {
  return wrapErrors(
    (async () => {
      if (!(sealed instanceof Uint8Array) || sealed.length < IV_BYTES + TAG_BYTES) throw new CryptoFailure("sealed item too short");
      const plain = await subtle.decrypt(
        { name: "AES-GCM", iv: sealed.slice(0, IV_BYTES), additionalData: utf8(`palabra-mirror-item-v1|${itemId}`), tagLength: 128 },
        keys.aes,
        sealed.slice(IV_BYTES),
      );
      return new Uint8Array(plain);
    })(),
  );
}

export function generatePairKeys() {
  return wrapErrors(
    (async () => {
      const pair = await subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
      return { privateKey: pair.privateKey, publicRaw: new Uint8Array(await subtle.exportKey("raw", pair.publicKey)) };
    })(),
  );
}

export function deriveKPair(privateKey, otherPublicRaw, nonce) {
  return wrapErrors(
    (async () => {
      if (!(otherPublicRaw instanceof Uint8Array) || otherPublicRaw.length !== 65 || otherPublicRaw[0] !== 4) throw new CryptoFailure("bad public key");
      if (!(nonce instanceof Uint8Array) || nonce.length !== 16) throw new CryptoFailure("bad nonce");
      const pub = await subtle.importKey("raw", otherPublicRaw, { name: "ECDH", namedCurve: "P-256" }, false, []);
      const shared = await subtle.deriveBits({ name: "ECDH", public: pub }, privateKey, 256);
      const base = await subtle.importKey("raw", shared, "HKDF", false, ["deriveKey"]);
      return subtle.deriveKey(
        { name: "HKDF", hash: "SHA-256", salt: nonce, info: utf8("palabra-mirror-pair-v1") },
        base,
        { name: "AES-GCM", length: 256 },
        false,
        ["encrypt", "decrypt"],
      );
    })(),
  );
}

/** Four digits both screens show; the person compares them before anything is released. */
export function matchCode(browserPub, phonePub, nonce) {
  return wrapErrors(
    (async () => {
      const digest = new Uint8Array(await subtle.digest("SHA-256", concat(browserPub, phonePub, nonce)));
      const n = new DataView(digest.buffer).getUint32(0, false);
      return String(n % 10000).padStart(4, "0");
    })(),
  );
}

export function openWrap(kPair, pairId, sealed) {
  return wrapErrors(
    (async () => {
      if (!(sealed instanceof Uint8Array) || sealed.length < IV_BYTES + TAG_BYTES) throw new CryptoFailure("wrap too short");
      const plain = await subtle.decrypt(
        { name: "AES-GCM", iv: sealed.slice(0, IV_BYTES), additionalData: utf8(`palabra-mirror-wrap-v1|${pairId}`), tagLength: 128 },
        kPair,
        sealed.slice(IV_BYTES),
      );
      const body = JSON.parse(new TextDecoder().decode(plain));
      const text = (v) => (typeof v === "string" && v.length > 0 && v.length <= 300 ? v : null);
      const mirrorId = text(body?.mirrorId);
      const deviceId = text(body?.deviceId);
      const deviceToken = text(body?.deviceToken);
      if (body?.v !== 1 || !mirrorId || !deviceId || !deviceToken) throw new CryptoFailure("bad wrap");
      const dataKey = decode(body.dataKey);
      if (dataKey.length !== 32) throw new CryptoFailure("bad data key");
      // Computers paired before key rotation existed got no device key.
      let deviceKey = null;
      if (body.deviceKey !== undefined && body.deviceKey !== null) {
        deviceKey = decode(body.deviceKey);
        if (deviceKey.length !== 32) throw new CryptoFailure("bad device key");
      }
      return { mirrorId, deviceId, deviceToken, dataKey, deviceKey };
    })(),
  );
}

/** This computer's own key, used only to open the key the phone sends after a rotation. Non-extractable, decrypt only. */
export function importDeviceKey(raw) {
  return wrapErrors(
    (async () => {
      if (!(raw instanceof Uint8Array) || raw.length !== 32) throw new CryptoFailure("device key must be 32 bytes");
      return subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["decrypt"]);
    })(),
  );
}

/** Opens the rotation blob for (mirrorId, deviceId, epoch). The epoch inside must be the one asked for. */
export function openRotation(deviceKey, mirrorId, deviceId, epoch, sealed) {
  return wrapErrors(
    (async () => {
      if (!(sealed instanceof Uint8Array) || sealed.length < IV_BYTES + TAG_BYTES) throw new CryptoFailure("rotation blob too short");
      if (!Number.isInteger(epoch) || epoch < 1) throw new CryptoFailure("bad epoch");
      const plain = await subtle.decrypt(
        { name: "AES-GCM", iv: sealed.slice(0, IV_BYTES), additionalData: utf8(`palabra-mirror-rotate-v1|${mirrorId}|${deviceId}|${epoch}`), tagLength: 128 },
        deviceKey,
        sealed.slice(IV_BYTES),
      );
      const body = JSON.parse(new TextDecoder().decode(plain));
      if (body?.v !== 1 || body.epoch !== epoch) throw new CryptoFailure("bad rotation");
      const dataKey = decode(body.dataKey);
      if (dataKey.length !== 32) throw new CryptoFailure("bad data key");
      return { epoch, dataKey };
    })(),
  );
}
