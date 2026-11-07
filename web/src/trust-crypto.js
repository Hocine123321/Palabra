// Automatic pairing: the crypto a phone and a browser use to trust each other after the person taps "Trust" on the phone.
// Protocol: docs/superpowers/specs/2026-11-07-web-companion-phase6-auto-pair.md. WebCrypto only.
// Each end makes a one-time P-256 key pair and exchanges the public halves through the lobby. The match code and the
// shared key both depend on BOTH public keys, so a man in the middle who swaps a key shows a different code and gets a
// different key. The phone then seals the link secret, a trust token and its relay address under that key.

import { toHex, fromHex, randomBytes, SECRET_BYTES } from "./link-crypto.js";

const trustEnc = new TextEncoder();
export const TOKEN_BYTES = 32;
export const PUBLIC_KEY_BYTES = 65;     // uncompressed P-256 point

/** A one-time key pair. `pub` is the raw public key as hex, safe to send through the lobby. */
export async function makeTrustKeys() {
  const pair = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const pub = toHex(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  return { privateKey: pair.privateKey, pub };
}

async function trustSha256(...parts) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const all = new Uint8Array(total);
  let at = 0;
  for (const p of parts) { all.set(p, at); at += p.length; }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", all));
}

function trustPublicBytes(hex) {
  const bytes = fromHex(hex);
  if (bytes.length !== PUBLIC_KEY_BYTES || bytes[0] !== 4) throw new Error("bad public key");
  return bytes;
}

/** Four digits both screens show. Same digits only if the two ends saw each other's real public keys. */
export async function matchCode(phonePub, browserPub) {
  const digest = await trustSha256(trustEnc.encode("palabra-match-v1"), trustPublicBytes(phonePub), trustPublicBytes(browserPub));
  const n = ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) >>> 0;
  return String(n % 10000).padStart(4, "0");
}

async function trustSharedKey(myPrivate, theirPubHex, phonePub, browserPub) {
  const theirs = await crypto.subtle.importKey("raw", trustPublicBytes(theirPubHex), { name: "ECDH", namedCurve: "P-256" }, false, []);
  const bits = await crypto.subtle.deriveBits({ name: "ECDH", public: theirs }, myPrivate, 256);
  const salt = await trustSha256(trustPublicBytes(phonePub), trustPublicBytes(browserPub));
  const base = await crypto.subtle.importKey("raw", new Uint8Array(bits), "HKDF", false, ["deriveBits"]);
  const raw = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info: trustEnc.encode("palabra-trust-v1") }, base, 256));
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Layout of what the phone grants: secret(32) | token(32) | relay address (UTF-8, the rest). */
export function packGrant({ secret, token, relayUrl }) {
  if (secret.length !== SECRET_BYTES || token.length !== TOKEN_BYTES) throw new Error("bad grant");
  const relay = trustEnc.encode(String(relayUrl || "").trim().slice(0, 200));
  const out = new Uint8Array(SECRET_BYTES + TOKEN_BYTES + relay.length);
  out.set(secret, 0); out.set(token, SECRET_BYTES); out.set(relay, SECRET_BYTES + TOKEN_BYTES);
  return out;
}

export function unpackGrant(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < SECRET_BYTES + TOKEN_BYTES) throw new Error("bad grant");
  return {
    secret: bytes.slice(0, SECRET_BYTES),
    token: bytes.slice(SECRET_BYTES, SECRET_BYTES + TOKEN_BYTES),
    relayUrl: new TextDecoder().decode(bytes.subarray(SECRET_BYTES + TOKEN_BYTES)).trim(),
  };
}

/** Phone side (also used by tests): seal a grant for the browser that asked. */
export async function sealGrant({ phonePrivate, phonePub, browserPub, grant, iv = randomBytes(12) }) {
  const key = await trustSharedKey(phonePrivate, browserPub, phonePub, browserPub);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: trustEnc.encode("palabra-grant-v1") }, key, packGrant(grant)));
  return { iv: toHex(iv), sealed: toHex(ct) };
}

/** Page side: open the grant. Throws if the keys do not match (a swapped key, a tampered message). */
export async function openGrant({ browserPrivate, phonePub, browserPub, iv, sealed }) {
  const key = await trustSharedKey(browserPrivate, phonePub, phonePub, browserPub);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: fromHex(iv), additionalData: trustEnc.encode("palabra-grant-v1") }, key, fromHex(sealed));
  return unpackGrant(new Uint8Array(pt));
}

/** The token is kept by the phone only as a hash, so a stolen phone backup does not hold a usable token. */
export async function tokenHash(token) {
  return toHex(await trustSha256(trustEnc.encode("palabra-token-v1"), token));
}
