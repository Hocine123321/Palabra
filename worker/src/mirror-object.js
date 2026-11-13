import { MirrorStore } from "./store.js";

const ABORT = Symbol("abort");
const UNAUTHORIZED = { ok: false, status: 401, error: "unauthorized" };

/**
 * What one Mirror Durable Object runs. Nothing is written until `create` succeeds, so a request for a
 * mirror id that does not exist leaves no storage behind (and answers 401, same as a wrong token).
 */
export class MirrorObject {
  constructor(sql, opts) {
    this.sql = sql;
    this.store = new MirrorStore(sql, opts);
    this.created = false;
  }

  ready() {
    if (this.created) return true;
    this.created = this.sql.all("SELECT 1 AS x FROM sqlite_master WHERE type = 'table' AND name = 'devices'").length > 0;
    return this.created;
  }

  create(args) {
    if (this.ready()) return this.store.create(args);
    let result;
    try {
      // Tables and owner row land together or not at all.
      this.sql.transaction(() => {
        this.store.init();
        result = this.store.create(args);
        if (!result.ok) throw ABORT;
      });
    } catch (e) {
      if (e !== ABORT) throw e;
    }
    this.created = result.ok;
    return result;
  }

  async addDevice(bearer, args) {
    return this.ready() ? this.store.addDevice(bearer, args) : UNAUTHORIZED;
  }
  async listDevices(bearer) {
    return this.ready() ? this.store.listDevices(bearer) : UNAUTHORIZED;
  }
  async removeDevice(bearer, deviceId) {
    return this.ready() ? this.store.removeDevice(bearer, deviceId) : UNAUTHORIZED;
  }
  async putItems(bearer, items) {
    return this.ready() ? this.store.putItems(bearer, items) : UNAUTHORIZED;
  }
  async listItems(bearer, since, limit) {
    return this.ready() ? this.store.listItems(bearer, since, limit) : UNAUTHORIZED;
  }
  async state(bearer) {
    return this.ready() ? this.store.state(bearer) : UNAUTHORIZED;
  }
  async rotate(bearer, body) {
    return this.ready() ? this.store.rotate(bearer, body) : UNAUTHORIZED;
  }
  async rotation(bearer) {
    return this.ready() ? this.store.rotation(bearer) : UNAUTHORIZED;
  }
}
