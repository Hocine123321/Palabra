import { DatabaseSync } from "node:sqlite";
import { GateStore } from "../../src/gate.js";
import { MirrorStore } from "../../src/store.js";
import { nodeSqlite } from "../../src/sql.js";
import { randomId } from "../../src/auth.js";
import { makeClock } from "./clock.js";

/** The router's backend over real stores on in-memory SQLite, with a controllable clock. */
export function makeMemoryBackend(opts = {}) {
  const clock = opts.clock ?? makeClock();
  const storeOpts = { now: clock.now, limits: opts.limits };
  const gate = new GateStore(nodeSqlite(new DatabaseSync(":memory:")), storeOpts);
  gate.init();
  const mirrors = new Map();
  return {
    clock,
    limits: opts.limits,
    gate,
    mirrors,
    async createMirror({ deviceId, ownerTokenHash }) {
      const store = new MirrorStore(nodeSqlite(new DatabaseSync(":memory:")), storeOpts);
      store.init();
      const created = store.create({ deviceId, ownerTokenHash });
      if (!created.ok) return created;
      const mirrorId = randomId();
      mirrors.set(mirrorId, store);
      return { ok: true, mirrorId };
    },
    mirror(mirrorId) {
      return mirrors.get(mirrorId) ?? null;
    },
  };
}
