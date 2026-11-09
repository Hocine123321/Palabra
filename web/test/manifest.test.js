import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { MANIFEST_KIND, MANIFEST_RECORD, checkCopy, idsHash, parseManifest } from "../src/manifest.js";

const vectors = JSON.parse(readFileSync(new URL("../../PalabraTests/Mirroring/Fixtures/mirror-vectors.json", import.meta.url), "utf8"));
const NOW = Date.parse("2026-11-09T21:30:00Z");
const row = (id, kind = "word") => ({ id, kind, recordId: `r-${id}`, g: 1, d: {} });

async function manifestRow(rows, over = {}, g = 5) {
  const live = rows.filter((r) => r.kind !== MANIFEST_KIND);
  const counts = {};
  for (const r of live) counts[r.kind] = (counts[r.kind] ?? 0) + 1;
  return { id: "manifestid", kind: MANIFEST_KIND, recordId: MANIFEST_RECORD, g, d: { counts, idsHash: await idsHash(live.map((r) => r.id)), pushedAt: "2026-11-09T21:30:00Z", ...over } };
}

test("constants", () => {
  assert.equal(MANIFEST_KIND, "manifest");
  assert.equal(MANIFEST_RECORD, "manifest");
});

test("idsHash equals the shared vector whatever the order, and the empty hash", async () => {
  const { ids, idsHashHex } = vectors.manifest;
  assert.equal(await idsHash(ids), idsHashHex);
  assert.equal(await idsHash([...ids].reverse()), idsHashHex);
  assert.equal(await idsHash([]), vectors.empty.idsHashHex);
});

test("parseManifest accepts a good row and reads the time in ms", async () => {
  const rows = [row("a"), row("b")];
  const parsed = parseManifest(await manifestRow(rows), NOW);
  assert.equal(parsed.generation, 5);
  assert.deepEqual(parsed.counts, { word: 2 });
  assert.equal(parsed.pushedAt, NOW);
  assert.equal(parsed.idsHash.length, 64);
});

test("parseManifest rejects every malformed shape", async () => {
  const good = await manifestRow([row("a")]);
  const bad = (d) => parseManifest({ ...good, d }, NOW);
  assert.equal(parseManifest({ ...good, kind: "word" }, NOW), null);
  assert.equal(bad({ ...good.d, counts: "word" }), null);
  assert.equal(bad({ ...good.d, counts: { word: 0 } }), null);
  assert.equal(bad({ ...good.d, counts: { word: 1.5 } }), null);
  assert.equal(bad({ ...good.d, counts: { word: 10_000_001 } }), null);
  assert.equal(bad({ ...good.d, idsHash: good.d.idsHash.slice(1) }), null);
  assert.equal(bad({ ...good.d, idsHash: good.d.idsHash.toUpperCase() }), null);
  assert.equal(bad(undefined), null);
  assert.equal(bad(null), null);
  assert.equal(parseManifest(null, NOW), null);
});

test("parseManifest drops an unreadable or future time but keeps the manifest", async () => {
  const good = await manifestRow([row("a")]);
  assert.equal(parseManifest({ ...good, d: { ...good.d, pushedAt: "banana" } }, NOW).pushedAt, null);
  assert.equal(parseManifest({ ...good, d: { ...good.d, pushedAt: "2026-11-09T22:30:00Z" } }, NOW).pushedAt, null);
  assert.equal(parseManifest({ ...good, d: { ...good.d, pushedAt: 5 } }, NOW).pushedAt, null);
  assert.equal(parseManifest({ ...good, d: { ...good.d, pushedAt: "2026-11-09T21:32:00Z" } }, NOW).pushedAt, Date.parse("2026-11-09T21:32:00Z"), "a minute or two of clock drift is fine");
});

test("checkCopy: verified, incomplete (missing, stray), unverified (none, garbage), highest g wins", async () => {
  const rows = [row("a"), row("b"), row("c"), row("d", "deck")];
  const manifest = await manifestRow(rows);
  const ok = await checkCopy([...rows, manifest], NOW);
  assert.deepEqual(ok, { state: "verified", generation: 5, pushedAt: NOW });

  assert.equal((await checkCopy([...rows.slice(1), manifest], NOW)).state, "incomplete", "a withheld item");
  assert.equal((await checkCopy([...rows, row("zzz"), manifest], NOW)).state, "incomplete", "a stray row");

  assert.deepEqual(await checkCopy(rows, NOW), { state: "unverified", generation: null, pushedAt: null });
  const garbage = { ...manifest, d: { counts: "x" } };
  assert.deepEqual(await checkCopy([...rows, garbage], NOW), { state: "unverified", generation: null, pushedAt: null });

  const older = await manifestRow(rows.slice(1), {}, 4);
  older.id = "manifestid2";
  assert.equal((await checkCopy([...rows, older, manifest], NOW)).state, "verified", "the manifest with the higher g decides");
  assert.equal((await checkCopy([...rows.slice(1), older, { ...manifest, g: 3 }], NOW)).state, "verified");
});
