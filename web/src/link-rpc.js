// Request/response over the encrypted link. A page calls `rpc.request("read", {...})` and gets the phone's answer.
// Replies are matched by id; replies too big for one relay frame arrive as `chunk` messages and are put back together.
// Everything here is pure (it takes a `send` function and is fed incoming messages), so Node tests drive it directly.

export class LinkRpcError extends Error {
  constructor(kind, message) { super(message); this.kind = kind; }
}

export function createRpc({ send, timeoutMs = 15000, setTimer = setTimeout, clearTimer = clearTimeout }) {
  let counter = 0;
  const waiting = new Map();   // id -> {resolve, reject, timer}
  const partial = new Map();   // id -> {total, parts: Map(index -> base64)}

  function settle(message) {
    const entry = waiting.get(message.id);
    if (!entry) return;
    waiting.delete(message.id);
    clearTimer(entry.timer);
    if (message.type === "reject") entry.reject(new LinkRpcError(message.payload?.reason ?? "rejected", reasonText(message.payload?.reason)));
    else entry.resolve(message.payload);
  }

  return {
    /** Feed every decrypted incoming message here. */
    receive(message) {
      if (message.type === "chunk") {
        const { index, total, data } = message.payload ?? {};
        if (!Number.isInteger(index) || !Number.isInteger(total) || total < 1 || index < 0 || index >= total || typeof data !== "string") return;
        let entry = partial.get(message.id);
        if (!entry || entry.total !== total) { entry = { total, parts: new Map() }; partial.set(message.id, entry); }
        entry.parts.set(index, data);
        if (entry.parts.size < total) return;
        partial.delete(message.id);
        const bytes = [];
        for (let i = 0; i < total; i++) bytes.push(base64ToBytes(entry.parts.get(i)));
        const whole = new Uint8Array(bytes.reduce((n, b) => n + b.length, 0));
        let at = 0; for (const b of bytes) { whole.set(b, at); at += b.length; }
        try { settle(JSON.parse(new TextDecoder().decode(whole))); } catch { /* a damaged reply is dropped; the request times out */ }
        return;
      }
      if (message.type === "ack" || message.type === "reject") settle(message);
    },

    /** Resolves with the reply payload; rejects with LinkRpcError (kind: a reason code, or "no-answer"). */
    request(type, payload) {
      const id = `q${++counter}`;
      return new Promise((resolve, reject) => {
        const timer = setTimer(() => {
          if (waiting.delete(id)) { partial.delete(id); reject(new LinkRpcError("no-answer", reasonText("no-answer"))); }
        }, timeoutMs);
        waiting.set(id, { resolve, reject, timer });
        // `send` may throw at once or reject later; both end the request with a LinkRpcError, never a raw error.
        new Promise((done) => done(send({ id, type, version: 1, payload }))).catch((e) => {
          if (waiting.delete(id)) { clearTimer(timer); reject(new LinkRpcError("send-failed", String(e?.message ?? e))); }
        });
      });
    },

    /** Everything still waiting is failed, e.g. when the link drops. */
    failAll(kind = "link-lost") {
      for (const [id, entry] of waiting) { clearTimer(entry.timer); entry.reject(new LinkRpcError(kind, reasonText(kind))); }
      waiting.clear(); partial.clear();
    },
    pending: () => waiting.size,
  };
}

export function reasonText(reason) {
  switch (reason) {
    case "no-answer": return "The phone did not answer. Keep Palabra open on screen.";
    case "link-lost": return "The link to the phone was lost.";
    case "forbidden": return "That is not allowed from the web.";
    case "bad-args": case "bad-request": return "The phone could not understand the request.";
    case "rate-limited": return "Too many requests. Wait a moment.";
    case "conflict": return "This changed on the phone after you looked at it.";
    case "not-found": return "That word is no longer on the phone.";
    case "live-only": return "This needs the phone connected right now.";
    case "not-queueable": return "This cannot wait in the queue.";
    default: return "The phone could not do that.";
  }
}

function base64ToBytes(text) {
  const bin = atob(text);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
