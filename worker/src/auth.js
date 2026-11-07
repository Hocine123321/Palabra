// Token helpers. Web Crypto only, so the same file runs in Node (tests) and in workerd.

const B64URL = /^[A-Za-z0-9_-]+$/;

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function randomId(bytes = 16) {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  let binary = "";
  for (const b of data) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** "Bearer <deviceId>.<token>" -> {deviceId, token}, or null for anything else. */
export function parseBearer(header) {
  if (typeof header !== "string" || header.length > 300 || !header.startsWith("Bearer ")) return null;
  const parts = header.slice(7).split(".");
  if (parts.length !== 2) return null;
  const [deviceId, token] = parts;
  if (!B64URL.test(deviceId) || !B64URL.test(token)) return null;
  return { deviceId, token };
}

/** Compares every character, no early exit. */
export function timingSafeEqualHex(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function isHex64(s) {
  return typeof s === "string" && /^[0-9a-f]{64}$/.test(s);
}

export function isB64url(s, min, max) {
  return typeof s === "string" && s.length >= min && s.length <= max && B64URL.test(s);
}
