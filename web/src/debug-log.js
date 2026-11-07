// The page's flight recorder. Everything the page does with the link (relay, presence, requests, sync, pairing, errors) is written
// here with a time, so "what is it doing right now?" can be answered by reading it instead of guessing.
//
// Privacy: the log can be copied and pasted into a chat, so it never holds a secret or a word of your data. Hex runs (secrets,
// tokens, keys) are cut to a short fingerprint, URLs lose their path (the room id is derived from the secret), and message
// payloads are described by type, id and size only. Pure module: tests drive it directly.

export const MAX_ENTRIES = 600;
const LEVELS = ["info", "warn", "error"];

/** Hides anything secret-looking. Long hex or base64 runs become `ab12…(64)`; relay URLs keep only their host. */
export function scrub(value) {
  let text = typeof value === "string" ? value : safeString(value);
  text = text.replace(/\b(wss?|https?):\/\/([a-z0-9.:-]+)(\/[^\s"'),;]*)?/gi, (_all, scheme, host, rest) => `${scheme}://${host}${rest ? "/…" : ""}`);
  text = text.replace(/\b[0-9a-fA-F]{24,}\b/g, (run) => `${run.slice(0, 4)}…(${run.length})`);
  text = text.replace(/[A-Za-z0-9+\/=_-]{40,}/g, (run) => `${run.slice(0, 4)}…(${run.length})`);
  return text.length > 400 ? `${text.slice(0, 400)}…` : text;
}

function safeString(value) {
  if (value === undefined) return "";
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  try { return typeof value === "object" ? JSON.stringify(value) : String(value); } catch { return String(value); }
}

/** Describes a protocol message without its content: `request snapshot #3 (212 B)`. */
export function describeMessage(message) {
  if (!message || typeof message !== "object") return "unreadable message";
  let size = 0;
  try { size = JSON.stringify(message.payload ?? null).length; } catch { size = 0; }
  const reason = message.type === "reject" && message.payload?.reason ? ` reason=${scrub(message.payload.reason)}` : "";
  return `${scrub(message.type ?? "?")} #${scrub(message.id ?? "?")} (${size} B)${reason}`;
}

export function createDebugLog({ now = () => Date.now(), max = MAX_ENTRIES } = {}) {
  let entries = [], listeners = [], seq = 0, enabled = true;
  const t0 = now();

  function add(level, area, text, detail) {
    if (!enabled) return;
    const entry = { n: ++seq, at: now(), ms: now() - t0, level: LEVELS.includes(level) ? level : "info", area: scrub(area), text: scrub(text) };
    if (detail !== undefined) entry.detail = scrub(detail);
    entries.push(entry);
    if (entries.length > max) entries = entries.slice(entries.length - max);
    for (const listener of listeners) { try { listener(entry); } catch { /* a broken view must never break the page */ } }
  }

  return {
    info: (area, text, detail) => add("info", area, text, detail),
    warn: (area, text, detail) => add("warn", area, text, detail),
    error: (area, text, detail) => add("error", area, text, detail),
    /** A function shaped like `(area, text, detail)` for the lower layers, which must not know about levels. */
    sink: (level = "info") => (area, text, detail) => add(level, area, text, detail),
    get entries() { return entries.slice(); },
    get size() { return entries.length; },
    onEntry(listener) { listeners.push(listener); return () => { listeners = listeners.filter((l) => l !== listener); }; },
    clear() { entries = []; },
    pause(on) { enabled = !on; },
    /** Plain text for copying: one line per entry, oldest first. */
    toText({ filter = "", level = "" } = {}) {
      return list(entries, filter, level).map(line).join("\n");
    },
    list: (opts = {}) => list(entries, opts.filter ?? "", opts.level ?? ""),
    line,
  };
}

function list(entries, filter, level) {
  const needle = String(filter ?? "").trim().toLowerCase();
  const rank = Math.max(0, LEVELS.indexOf(level));
  return entries.filter((e) => LEVELS.indexOf(e.level) >= rank && (!needle || `${e.area} ${e.text} ${e.detail ?? ""}`.toLowerCase().includes(needle)));
}

function line(e) {
  const secs = (e.ms / 1000).toFixed(2).padStart(7, " ");
  const mark = e.level === "error" ? "ERR " : e.level === "warn" ? "WARN" : "    ";
  return `${secs}s ${mark} [${e.area}] ${e.text}${e.detail ? ` | ${e.detail}` : ""}`;
}
