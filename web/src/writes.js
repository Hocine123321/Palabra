// Connects the outbox to the encrypted link, and offers the live-only AI call. Small on purpose.
import { LiveOnlyError, LIVE_ONLY } from "./outbox.js";

/** A `send` for the outbox: one waiting action goes to the phone as a `write`. Resolves on a confirmed reply. */
export function sendOutboxItem(getLink) {
  return async (item) => {
    const link = getLink();
    if (!link) throw Object.assign(new Error("no link"), { kind: "no-answer" });
    // The id lets the phone recognise a retry after a lost reply and answer with the first result instead of acting twice.
    return link.request("write", { id: item.id, capability: item.capability, args: item.args, base: item.base });
  };
}

/** AI calls: only with a live link, answered or failed right now, never stored. */
export async function callAiLive(getLink, args) {
  const link = getLink();
  if (!link) throw new LiveOnlyError("ai.generate");
  return link.request("ai", { args });
}

export { LIVE_ONLY };

/**
 * The `base` for a words.place: for every word the change touches, the placement token of what the page saw. The phone
 * refuses the whole action if any of them no longer matches. `words` is the snapshot's word list.
 */
export function placementBase(words, refs, tokenOf) {
  const base = {};
  for (const ref of refs) {
    const w = words.find((x) => x.id === ref || x.key === ref);
    if (w) base[ref] = tokenOf(w.category ?? null, w.tags ?? []);
  }
  return base;
}

/**
 * Turns what the person typed ("hola, adiós,  buenas noches") into the words to add. Splits on commas and new lines,
 * trims, drops empties and repeats (ignoring case), keeps each to the phone's 80 characters, and at most 20 per action.
 */
export function parseWords(text) {
  const seen = new Set(), out = [];
  for (const raw of String(text ?? "").split(/[,\n;،]/)) {
    const word = raw.trim().replace(/\s+/g, " ");
    if (!word || word.length > 80) continue;
    const key = word.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key); out.push(word);
    if (out.length === 20) break;
  }
  return out;
}
