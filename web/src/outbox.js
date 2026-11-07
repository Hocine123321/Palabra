// The outbox: changes made on the page while the phone may be away. Kept in order, sent one at a time, never sent twice
// (each action has an id the phone remembers), and when the phone disagrees the action moves to "needs review" for the
// person to retry, edit or drop. Pure logic over an injected store, a sender and a clock, so it is tested in Node.
//
// What may be queued is decided here AND on the phone. Costly or irreversible things never wait in a queue: they need a live,
// confirmed link at the moment the person presses the button.

/** Actions that may wait for the phone. Anything else must be sent live or not at all. */
export const QUEUEABLE = new Set(["words.add", "words.place", "review.flag"]);
/** Actions that need the phone right now: they spend quota, so a stale queue must never fire them silently. */
export const LIVE_ONLY = new Set(["ai.generate"]);

const KEY = "outbox";
export const MAX_QUEUED = 200;   // a runaway page must not fill the browser

export class LiveOnlyError extends Error {
  constructor(name) { super(`${name} needs the phone to be connected right now`); this.kind = "live-only"; }
}

export function createOutbox({ store, send, onChange = () => {}, newId = () => crypto.randomUUID(), now = () => new Date() }) {
  let state = { schema: 1, queue: [], review: [] };
  let sending = false;

  const persist = async () => { try { await store.set(KEY, state); } catch { /* the in-memory queue still works for this visit */ } };
  const publish = () => onChange({ waiting: state.queue.length, review: state.review.map((r) => ({ ...r })), queue: state.queue.map((q) => ({ ...q })) });

  return {
    async load() {
      try {
        const saved = await store.get(KEY);
        if (saved && saved.schema === 1 && Array.isArray(saved.queue) && Array.isArray(saved.review)) state = saved;
      } catch { /* start empty */ }
      publish();
    },

    /** Adds an action. `base` is what the page saw of the record (the phone compares it). Returns the queued item. */
    async enqueue(capability, args, base = null) {
      if (LIVE_ONLY.has(capability)) throw new LiveOnlyError(capability);
      if (!QUEUEABLE.has(capability)) throw Object.assign(new Error(`${capability} cannot be queued`), { kind: "not-queueable" });
      if (state.queue.length >= MAX_QUEUED) throw Object.assign(new Error("too many waiting changes"), { kind: "full" });
      const item = { id: newId(), capability, args, base, at: now().toISOString(), tries: 0 };
      state.queue.push(item);
      await persist(); publish();
      return item;
    },

    /**
     * Sends waiting actions oldest first. Stops at the first one the phone does not answer (order matters, and the phone is
     * probably gone). An answered refusal moves that one to review and carries on with the next.
     */
    async flush() {
      if (sending) return { sent: 0, rejected: 0 };
      sending = true;
      let sent = 0, rejected = 0;
      try {
        while (state.queue.length) {
          const item = state.queue[0];
          // Re-check at the last moment: the stored queue is just bytes in the browser and could have been altered.
          if (!QUEUEABLE.has(item.capability)) {
            state.queue.shift();
            state.review.push({ ...item, reason: "not-queueable", message: `${item.capability} cannot be queued`, rejectedAt: now().toISOString() });
            rejected += 1;
            continue;
          }
          let reply;
          try {
            reply = await send(item);
          } catch (error) {
            item.tries += 1;
            if (error?.kind === "no-answer" || error?.kind === "link-lost") break;   // phone away: keep everything, try later
            // The phone answered with a refusal.
            state.queue.shift();
            state.review.push({ ...item, reason: error?.kind ?? "failed", message: error?.message ?? "", rejectedAt: now().toISOString() });
            rejected += 1;
            continue;
          }
          state.queue.shift();
          sent += 1;
          void reply;
        }
      } finally {
        sending = false;
        await persist(); publish();
      }
      return { sent, rejected };
    },

    /** Review list actions. */
    async retry(id) {
      const i = state.review.findIndex((r) => r.id === id);
      if (i < 0) return false;
      const { reason, message, rejectedAt, ...item } = state.review.splice(i, 1)[0];
      state.queue.push({ ...item, base: null, tries: 0 });   // retrying means "do it anyway": the old base no longer applies
      await persist(); publish();
      return true;
    },
    async drop(id) {
      const before = state.review.length;
      state.review = state.review.filter((r) => r.id !== id);
      await persist(); publish();
      return state.review.length < before;
    },
    /** Removes a waiting action the person changed their mind about. */
    async cancel(id) {
      const before = state.queue.length;
      state.queue = state.queue.filter((q) => q.id !== id);
      await persist(); publish();
      return state.queue.length < before;
    },
    /** Forget: empties the queue AND removes the stored record, so nothing of the person's changes is left in the browser. */
    async clear() {
      state = { schema: 1, queue: [], review: [] };
      try { await store.delete(KEY); } catch { /* nothing stored, or the browser refused */ }
      publish();
    },
    get snapshot() { return { waiting: state.queue.length, review: state.review.length }; },
  };
}
