// The only file that imports from "cloudflare:workers". Thin wrappers: all behaviour is in the stores.
import { DurableObject } from "cloudflare:workers";
import { GateStore } from "./gate.js";
import { MirrorObject } from "./mirror-object.js";
import { durableSql } from "./sql.js";
import { randomId } from "./auth.js";

/** Singleton: pairing slots and per-IP rate counters. */
export class Gate extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.store = new GateStore(durableSql(ctx.storage));
    this.store.init();
  }
  rate(key, limit, windowSec) {
    return this.store.rate(key, limit, windowSec);
  }
  startPairing() {
    return this.store.startPairing();
  }
  joinPairing(pairId, phonePub) {
    return this.store.joinPairing(pairId, phonePub);
  }
  replyPairing(pairId, sealed) {
    return this.store.replyPairing(pairId, sealed);
  }
  getPairing(pairId) {
    return this.store.getPairing(pairId);
  }
  cancelPairing(pairId) {
    return this.store.cancelPairing(pairId);
  }
}

/** One per mirror id: devices and sealed items. */
export class Mirror extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.object = new MirrorObject(durableSql(ctx.storage));
  }
  create(args) {
    return this.object.create(args);
  }
  addDevice(bearer, args) {
    return this.object.addDevice(bearer, args);
  }
  listDevices(bearer) {
    return this.object.listDevices(bearer);
  }
  removeDevice(bearer, deviceId) {
    return this.object.removeDevice(bearer, deviceId);
  }
  putItems(bearer, items) {
    return this.object.putItems(bearer, items);
  }
  listItems(bearer, since, limit) {
    return this.object.listItems(bearer, since, limit);
  }
  state(bearer) {
    return this.object.state(bearer);
  }
}

/** The router's backend over the two Durable Object namespaces. */
export function doBackend(env) {
  return {
    gate: env.GATE.getByName("gate"),
    async createMirror({ deviceId, ownerTokenHash }) {
      const mirrorId = randomId(16);
      const made = await env.MIRROR.getByName(mirrorId).create({ deviceId, ownerTokenHash });
      return made.ok ? { ok: true, mirrorId } : made;
    },
    mirror: (mirrorId) => env.MIRROR.getByName(mirrorId),
  };
}
