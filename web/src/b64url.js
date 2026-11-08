// Unpadded base64url, strict: anything outside the alphabet (including "=", "+", "/") is an error.

const ALPHABET = /^[A-Za-z0-9_-]*$/;

export function encode(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function decode(text) {
  if (typeof text !== "string" || !ALPHABET.test(text) || text.length % 4 === 1) throw new Error("bad base64url");
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
