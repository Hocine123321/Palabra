// The files the service worker keeps for offline use, and the version that names their cache.
import { createHash } from "node:crypto";

/** Paths as the browser asks for them. "/" is index.html. Order matters: it is part of the version. */
export const SHELL = ["/", "/app.js", "/app.css", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon-512.png"];

/** First 12 hex characters of SHA-256 over every shell file's path and bytes, in shell order. `files`: Map path -> Buffer. */
export function versionFor(files) {
  const hash = createHash("sha256");
  for (const path of SHELL.filter((p) => files.has(p))) {
    hash.update(path);
    hash.update("\0");
    hash.update(files.get(path));
    hash.update("\0");
  }
  return hash.digest("hex").slice(0, 12);
}
