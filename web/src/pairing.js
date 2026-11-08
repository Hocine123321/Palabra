// The browser side of pairing. The private key lives only in this object's memory.
import { ApiError } from "./api.js";
import { decode, encode } from "./b64url.js";
import { CryptoFailure, deriveKPair, generatePairKeys, matchCode, openWrap } from "./crypto.js";

/** The slot lives 120 s on the server; the local deadline avoids trusting the two clocks to agree. */
const PAIR_TTL_MS = 120_000;

export function createPairing({ api, origin, now = Date.now }) {
  let s = null;

  const started = () => {
    if (!s) throw new Error("pairing has not started");
    return s;
  };

  return {
    async start() {
      const keys = await generatePairKeys();
      const nonce = crypto.getRandomValues(new Uint8Array(16));
      const { pairId } = await api.pairStart();
      s = { ...keys, nonce, pairId, expiresAt: now() + PAIR_TTL_MS, phonePub: null, sealed: null, code: null, consumed: false };
      const link = `${origin}/#p=${pairId}&k=${encode(keys.publicRaw)}&n=${encode(nonce)}`;
      return { link, pairId, expiresAt: s.expiresAt };
    },

    async poll() {
      const p = started();
      if (p.sealed) return { state: "replied", code: p.code };
      if (now() > p.expiresAt) return { state: "expired" };
      let slot;
      try {
        slot = await api.pairGet(p.pairId);
      } catch (e) {
        if (e instanceof ApiError && (e.status === 410 || e.status === 404)) return { state: "expired" };
        throw e;
      }
      if (slot.state === "waiting" || slot.state === "cancelled") return { state: slot.state };
      if (slot.state !== "joined" && slot.state !== "replied") throw new Error("unexpected pairing state");
      const phonePub = decode(slot.phonePub ?? "");
      if (phonePub.length !== 65 || phonePub[0] !== 4) throw new CryptoFailure("bad phone key");
      p.phonePub = phonePub;
      p.code = await matchCode(p.publicRaw, phonePub, p.nonce);
      if (slot.state === "replied") {
        p.sealed = decode(slot.sealed ?? "");
        return { state: "replied", code: p.code };
      }
      return { state: "joined", code: p.code };
    },

    /** Opens the phone's reply. Call only after the person confirmed that both screens show the same code. */
    async accept() {
      const p = started();
      if (!p.sealed) throw new Error("the phone has not replied yet");
      if (p.consumed) throw new Error("already accepted");
      p.consumed = true;
      const kPair = await deriveKPair(p.privateKey, p.phonePub, p.nonce);
      return openWrap(kPair, p.pairId, p.sealed);
    },

    async cancel() {
      const p = started();
      try {
        await api.pairCancel(p.pairId);
      } catch (e) {
        if (!(e instanceof ApiError)) throw e;
      }
    },
  };
}
