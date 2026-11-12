// Small, total helpers for data that came from the phone: anything may be missing or the wrong type, nothing may throw.

export const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
export const arr = (v) => (Array.isArray(v) ? v : []);
/** Text, or "" for anything that is not a string or a number. */
export const str = (v) => (typeof v === "string" ? v : typeof v === "number" && Number.isFinite(v) ? String(v) : "");

/** A lesson string without its light markup: `{{term|id}}` and `[[target|e]]` keep their text, `**bold**` loses the stars. */
export function inline(value) {
  return str(value)
    .replace(/\{\{([^{}|]*)(?:\|[^{}]*)?\}\}/g, "$1")
    .replace(/\[\[([^[\]|]*)(?:\|[^[\]]*)?\]\]/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1");
}

export function formatTime(ms, lang) {
  try {
    if (!Number.isFinite(ms)) return "";
    return new Intl.DateTimeFormat(lang, { dateStyle: "medium", timeStyle: "short" }).format(new Date(ms));
  } catch {
    return "";
  }
}

/** ISO-8601 text from the phone -> milliseconds, or null. */
export const parseTime = (value) => {
  const ms = typeof value === "string" ? Date.parse(value) : NaN;
  return Number.isFinite(ms) ? ms : null;
};
