// The manifest: one sealed item the phone writes after its data items. It lists how many items of each kind exist and a hash
// of all their ids, so the page can tell a complete copy from a partial one. Protocol: docs/features/mirroring.md.

export const MANIFEST_KIND = "manifest";
export const MANIFEST_RECORD = "manifest";

const MAX_COUNT = 10_000_000;
const FUTURE_SLACK_MS = 5 * 60 * 1000;
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const toHex = (buffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");

/** Lowercase hex SHA-256 of the ids sorted by code point and joined with a newline. */
export async function idsHash(ids) {
  const text = [...ids].sort().join("\n");
  return toHex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

/** A manifest row -> {generation, counts, idsHash, pushedAt (ms or null)}, or null if anything about it is wrong. */
export function parseManifest(row, now = Date.now()) {
  if (!isObject(row) || row.kind !== MANIFEST_KIND || !Number.isFinite(row.g) || !isObject(row.d)) return null;
  const { counts, idsHash: hash, pushedAt } = row.d;
  if (!isObject(counts) || typeof hash !== "string" || !/^[0-9a-f]{64}$/.test(hash)) return null;
  for (const value of Object.values(counts)) {
    if (!Number.isInteger(value) || value < 1 || value > MAX_COUNT) return null;
  }
  let time = typeof pushedAt === "string" ? Date.parse(pushedAt) : NaN;
  if (!Number.isFinite(time) || time > now + FUTURE_SLACK_MS) time = null;
  return { generation: row.g, counts: { ...counts }, idsHash: hash, pushedAt: time };
}

/** Compares the local rows with the newest valid manifest among them. */
export async function checkCopy(rows, now = Date.now()) {
  const none = { state: "unverified", generation: null, pushedAt: null };
  const manifests = rows
    .filter((r) => r.kind === MANIFEST_KIND)
    .map((r) => parseManifest(r, now))
    .filter(Boolean)
    .sort((a, b) => b.generation - a.generation);
  const manifest = manifests[0];
  if (!manifest) return none;

  const live = rows.filter((r) => r.kind !== MANIFEST_KIND);
  const counts = {};
  for (const r of live) counts[r.kind] = (counts[r.kind] ?? 0) + 1;
  const sameCounts =
    Object.keys(counts).length === Object.keys(manifest.counts).length &&
    Object.entries(counts).every(([kind, n]) => manifest.counts[kind] === n);
  const sameIds = sameCounts && (await idsHash(live.map((r) => r.id))) === manifest.idsHash;
  return { state: sameIds ? "verified" : "incomplete", generation: manifest.generation, pushedAt: manifest.pushedAt };
}
