// Pure view-models for the read-only screens. No DOM: they take the snapshot the phone sent and return plain data,
// so the same code is tested in Node and run in the page.

/** Port of WordKey.tintIndex (FNV-1a over UTF-8). Same word, same tile colour as in the app. */
export function tintIndex(key, count = 6) {
  let hash = 2166136261;
  for (const byte of new TextEncoder().encode(String(key))) {
    hash = (hash ^ byte) >>> 0;
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash % count;
}

const fold = (s) => String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

/**
 * The Library screen's data. Words are newest first (as the phone sends them); `query` matches the Spanish word,
 * the translation, the section and the tags, ignoring case and accents; `tag` and `section` narrow further
 * (`section` left out = every section, `null` = only the unsectioned words).
 * Sections keep first-seen order, with the unsectioned words last.
 */
export function libraryView(snapshot, { query = "", tag = null, section } = {}) {
  const all = Array.isArray(snapshot?.words) ? snapshot.words : [];
  const q = fold(query.trim());
  const words = all.filter((w) => {
    if (tag && !(w.tags ?? []).some((t) => fold(t) === fold(tag))) return false;
    if (section !== undefined && (w.category ?? null) !== section) return false; // undefined = every section, null = only unsectioned
    if (!q) return true;
    return [w.spanish, w.translation, w.category, ...(w.tags ?? [])].some((s) => fold(s).includes(q));
  });
  const order = [];
  const groups = new Map();
  for (const w of words) {
    const name = w.category ?? null;
    if (!groups.has(name)) { groups.set(name, []); order.push(name); }
    groups.get(name).push({ ...w, tint: tintIndex(w.key ?? w.spanish) });
  }
  order.sort((a, b) => (a === null) - (b === null));
  const tags = [...new Set(all.flatMap((w) => w.tags ?? []))].sort((a, b) => fold(a).localeCompare(fold(b)));
  const sections = [...new Set(all.map((w) => w.category ?? null))].sort((a, b) => (a === null) - (b === null));
  return {
    total: all.length,
    shown: words.length,
    groups: order.map((name) => ({ name, words: groups.get(name) })),
    tags,
    sections,
    isEmpty: all.length === 0,
    noMatches: all.length > 0 && words.length === 0,
  };
}

/** The Study screen: decks with their due and new counts, and the words flagged for review (weakest first). */
export function studyView(snapshot) {
  const decks = (Array.isArray(snapshot?.decks) ? snapshot.decks : []).map((d) => ({
    id: d.id, name: d.name, kind: d.kind, total: d.total ?? 0, due: d.due ?? 0, new: d.new ?? 0,
  }));
  const review = (Array.isArray(snapshot?.review) ? snapshot.review : []).slice().sort((a, b) => (a.score ?? 0) - (b.score ?? 0));
  return {
    decks,
    review,
    dueTotal: decks.reduce((n, d) => n + d.due, 0),
    newTotal: decks.reduce((n, d) => n + d.new, 0),
    hasDecks: decks.length > 0,
    hasReview: review.length > 0,
  };
}

/** Added-per-day numbers for the small chart on Study; the phone sends oldest first. */
export function activityView(snapshot) {
  const days = Array.isArray(snapshot?.wordsPerDay) ? snapshot.wordsPerDay : [];
  const max = Math.max(1, ...days.map((d) => d.count ?? 0));
  return { days: days.map((d) => ({ day: d.day, count: d.count ?? 0, height: Math.round(((d.count ?? 0) / max) * 100) })), total: days.reduce((n, d) => n + (d.count ?? 0), 0) };
}

/** The pieces of "Synced 3 min ago": {kind: "never" | "now" | "ago", n, unit: "min" | "h" | "d"}. Words are the renderer's job. */
export function syncedParts(takenAt, now = new Date()) {
  if (!takenAt) return { kind: "never" };
  const seconds = Math.max(0, Math.round((now - new Date(takenAt)) / 1000));
  if (seconds < 45) return { kind: "now" };
  if (seconds < 3600) return { kind: "ago", n: Math.round(seconds / 60), unit: "min" };
  if (seconds < 86400) return { kind: "ago", n: Math.round(seconds / 3600), unit: "h" };
  return { kind: "ago", n: Math.round(seconds / 86400), unit: "d" };
}

/** English "Synced 3 min ago". */
export function syncedText(takenAt, now = new Date()) {
  const p = syncedParts(takenAt, now);
  return p.kind === "never" ? "Not synced yet" : p.kind === "now" ? "Synced just now" : `Synced ${p.n} ${p.unit} ago`;
}
