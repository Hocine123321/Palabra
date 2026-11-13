// Pulls the sealed items from the Worker, opens them and stores them in the local copy.
import { ApiError } from "./api.js";
import { decode } from "./b64url.js";
import { CryptoFailure, deriveItemId, importDataKey, openItem, openRotation } from "./crypto.js";
import { MANIFEST_KIND, checkCopy } from "./manifest.js";

export class AuthRevoked extends Error {
  constructor() {
    super("this computer was removed");
    this.name = "AuthRevoked";
  }
}

/** The server answered with older state than this computer already holds (a lower head seq, or an older manifest). */
export class RollbackDetected extends Error {
  constructor(reason) {
    super("the server sent older data than this computer already has");
    this.name = "RollbackDetected";
    this.reason = reason; // "seq" | "generation"
  }
}

const PAGE = 200;
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

/** One sealed item -> a row, or null if anything about it is wrong (bad seal, bad shape, id not derived from kind and record). */
async function openRow(keys, item) {
  try {
    const plain = await openItem(keys, item.id, decode(item.sealed));
    const env = JSON.parse(new TextDecoder().decode(plain));
    if (!isObject(env) || env.v !== 1 || typeof env.k !== "string" || typeof env.r !== "string") return null;
    if (!Number.isFinite(env.g) || env.g < 0 || !isObject(env.d)) return null;
    if ((await deriveItemId(keys, env.k, env.r)) !== item.id) return null;
    return { id: item.id, kind: env.k, recordId: env.r, g: env.g, d: env.d };
  } catch {
    return null;
  }
}

/** What the saved copy says about itself: verified, incomplete or unverified, and when the phone last pushed. */
export async function describeCopy(db) {
  return checkCopy(await db.allItems());
}

const revoked = (error) => error instanceof ApiError && (error.status === 401 || error.status === 403);

/**
 * The phone replaced the data key. Fetch this computer's sealed copy of the new one and open it with the device key from pairing.
 * Anything short of that (no blob, a blob for someone else or another epoch, a computer paired before device keys existed)
 * means this computer is no longer one of the phone's: it is told it was removed. Offline or a Worker error is not that.
 */
async function rekey(api, db, creds, bearer, workerEpoch) {
  if (!creds.deviceKey) throw new AuthRevoked();
  let answer;
  try {
    answer = await api.rotation(creds.mirrorId, bearer);
  } catch (error) {
    if (error instanceof ApiError && (error.status === 404 || revoked(error))) throw new AuthRevoked();
    throw error;
  }
  const epoch = answer?.epoch;
  if (!Number.isInteger(epoch) || epoch <= (creds.epoch ?? 0) || epoch < workerEpoch || typeof answer.blob !== "string") throw new AuthRevoked();
  let sealedBlob;
  try {
    sealedBlob = decode(answer.blob);
  } catch {
    throw new AuthRevoked(); // not base64url: nothing this computer can open
  }
  let keys;
  try {
    const { dataKey } = await openRotation(creds.deviceKey, creds.mirrorId, creds.deviceId, epoch, sealedBlob);
    keys = await importDataKey(dataKey);
  } catch (error) {
    if (error instanceof CryptoFailure) throw new AuthRevoked();
    throw error;
  }
  const next = { ...creds, keys, epoch };
  await db.replaceEpoch(next);
  return next;
}

export async function pullOnce({ api, db }) {
  let creds = await db.getCredentials();
  if (!creds) throw new Error("not paired");
  const bearer = `${creds.deviceId}.${creds.deviceToken}`;
  let state;
  try {
    state = await api.state(creds.mirrorId, bearer);
  } catch (error) {
    if (revoked(error)) throw new AuthRevoked();
    throw error;
  }
  if (Number.isInteger(state?.epoch) && state.epoch > (creds.epoch ?? 0)) creds = await rekey(api, db, creds, bearer, state.epoch);
  let since = await db.getLastSeq();
  if (Number.isFinite(state?.seq) && state.seq < since) throw new RollbackDetected("seq");
  let applied = 0;
  let deleted = 0;
  let rejected = 0;
  const savedManifests = await db.itemsByKind(MANIFEST_KIND);
  const savedGeneration = savedManifests.reduce((high, r) => Math.max(high, r.g), -Infinity);
  let first = true;

  for (;;) {
    let page;
    try {
      page = await api.items(creds.mirrorId, bearer, since, PAGE);
    } catch (error) {
      if (revoked(error)) throw new AuthRevoked();
      throw error;
    }
    if (first && Number.isFinite(page.seq) && page.seq < since) throw new RollbackDetected("seq");
    first = false;
    const rows = [];
    const deletes = [];
    for (const item of page.items) {
      if (item.deleted) {
        deletes.push(item.id);
        deleted += 1;
        continue;
      }
      const row = await openRow(creds.keys, item);
      if (row) {
        rows.push(row);
        applied += 1;
      } else {
        rejected += 1;
      }
    }
    if (rows.some((r) => r.kind === MANIFEST_KIND && r.g < savedGeneration)) throw new RollbackDetected("generation");
    // Continue from the last item's seq (page.seq is the mirror's head, not where this page ended); at the end, take the head.
    const lastItem = page.items.length ? page.items[page.items.length - 1].seq : since;
    const next = page.more ? lastItem : Math.max(lastItem, page.seq ?? 0);
    await db.applyPage(rows, deletes, next);
    since = next;
    if (!page.more || page.items.length === 0) break;
  }
  return { applied, deleted, rejected, seq: since, check: await describeCopy(db) };
}
