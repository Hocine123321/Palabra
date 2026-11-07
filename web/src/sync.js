// Keeps what the page shows in step with the phone. Pure logic over three injected pieces (cache, a link opener, a clock),
// so it is tested in Node with no browser, phone or network.
//
// States the page can be in:
//   "linked"      phone answered; data is fresh
//   "connecting"  trying (cached data, if any, is already on screen)
//   "away"        phone not reachable; showing the saved copy
//   "empty"       nothing saved and the phone is not reachable
//   "error"       something needs the person (e.g. the phone says the pairing was revoked)

export function createSync({ cache, openLink, onChange, now = () => new Date(), retryMs = [2000, 5000, 15000, 30000], setTimer = setTimeout, clearTimer = clearTimeout }) {
  const view = { state: "connecting", snapshot: null, takenAt: null, message: "", failures: 0, reason: "", step: "" };
  let link = null, stopped = false, attempt = 0, timer = null, busy = false;

  const emit = (patch) => { Object.assign(view, patch); onChange({ ...view }); };

  /** Shows the saved copy at once. Returns true if there was one. */
  async function showCached() {
    const saved = await cache.loadSnapshot();
    if (!saved) return false;
    emit({ snapshot: saved.snapshot, takenAt: saved.takenAt });
    return true;
  }

  async function connectOnce(secretHex, relayUrl) {
    const secret = Uint8Array.from(secretHex.match(/../g).map((h) => parseInt(h, 16)));
    emit({ step: "relay" });
    link = await openLink({ relayUrl, secret, onClose: () => { if (!stopped && view.state === "linked") api.linkLost(secretHex, relayUrl); } });
    emit({ step: "phone" });
    const reply = await link.request("snapshot");
    if (!reply?.snapshot || !reply.takenAt) throw Object.assign(new Error("bad snapshot"), { kind: "bad-reply" });
    await cache.saveSnapshot(reply.snapshot, reply.takenAt);   // a failed save must not hide fresh data
    attempt = 0;
    emit({ state: "linked", snapshot: reply.snapshot, takenAt: reply.takenAt, message: "", failures: 0, reason: "", step: "" });
  }

  async function run(secretHex, relayUrl) {
    if (busy || stopped) return;
    busy = true;
    try {
      emit({ state: "connecting" });
      await connectOnce(secretHex, relayUrl);
    } catch (error) {
      try { link?.close?.(); } catch { /* already closed */ }
      link = null;
      const hasData = view.snapshot !== null;
      const needsPerson = error?.kind === "forbidden" || error?.kind === "revoked";
      if (needsPerson) emit({ state: "error", message: error.message ?? "" });   // retrying cannot fix this: stop and say so
      else emit({ state: hasData ? "away" : "empty", message: "", failures: view.failures + 1, reason: error?.kind ?? "failed", step: "" });
      if (!stopped && !needsPerson) {
        const wait = retryMs[Math.min(attempt, retryMs.length - 1)];
        attempt += 1;
        timer = setTimer(() => { busy = false; run(secretHex, relayUrl); }, wait);
        return;           // `busy` stays set until the retry timer fires, so two retries never overlap
      }
    }
    busy = false;
  }

  const api = {
    get view() { return { ...view }; },
    /** The live link, or null while the phone is away. */
    get link() { return view.state === "linked" ? link : null; },
    showCached,
    /** Start (or restart) syncing with the phone. */
    start(secretHex, relayUrl) { stopped = false; attempt = 0; if (timer) clearTimer(timer); busy = false; return run(secretHex, relayUrl); },
    /** The link dropped (socket closed): fall back to the saved copy and try again. */
    linkLost(secretHex, relayUrl) {
      if (stopped) return;
      emit({ state: view.snapshot ? "away" : "empty" });
      busy = false; if (timer) clearTimer(timer);
      timer = setTimer(() => run(secretHex, relayUrl), retryMs[0]);
    },
    stop() { stopped = true; if (timer) clearTimer(timer); try { link?.close?.(); } catch { /* ignore */ } link = null; },
    /** Ask for fresh data now (e.g. a "Sync now" button); keeps the saved copy if the phone does not answer. */
    async refresh() {
      if (!link) return false;
      try {
        const reply = await link.request("snapshot");
        await cache.saveSnapshot(reply.snapshot, reply.takenAt);
        emit({ state: "linked", snapshot: reply.snapshot, takenAt: reply.takenAt });
        return true;
      } catch { emit({ state: "away" }); return false; }
    },
    get now() { return now(); },
  };
  return api;
}
