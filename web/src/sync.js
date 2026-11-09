// Pulls the sealed items from the Worker, opens them and stores them in the local copy.
import { ApiError } from "./api.js";
import { decode } from "./b64url.js";
import { deriveItemId, openItem } from "./crypto.js";

export class AuthRevoked extends Error {
  constructor() {
    super("this computer was removed");
    this.name = "AuthRevoked";
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

export async function pullOnce({ api, db }) {
  const creds = await db.getCredentials();
  if (!creds) throw new Error("not paired");
  const bearer = `${creds.deviceId}.${creds.deviceToken}`;
  let since = await db.getLastSeq();
  let applied = 0;
  let deleted = 0;
  let rejected = 0;

  for (;;) {
    let page;
    try {
      page = await api.items(creds.mirrorId, bearer, since, PAGE);
    } catch (error) {
      if (error instanceof ApiError && (error.status === 401 || error.status === 403)) throw new AuthRevoked();
      throw error;
    }
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
    // Continue from the last item's seq (page.seq is the mirror's head, not where this page ended); at the end, take the head.
    const lastItem = page.items.length ? page.items[page.items.length - 1].seq : since;
    const next = page.more ? lastItem : Math.max(lastItem, page.seq ?? 0);
    await db.applyPage(rows, deletes, next);
    since = next;
    if (!page.more || page.items.length === 0) break;
  }
  return { applied, deleted, rejected, seq: since };
}
