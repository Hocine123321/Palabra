// Hash routes. Anything unknown goes to the words list; ids are kept exactly as they appear (they are base64url item ids).

const WITH_ID = { words: "word", artifacts: "artifact", books: "book" };
const WITHOUT_ID = { study: "study", review: "review", chat: "chat" };

/** "#/words/abc" -> {name: "word", id: "abc"}. */
export function parseRoute(hash) {
  const parts = String(hash ?? "").replace(/^#/, "").split("/"); // "/words/abc" -> ["", "words", "abc"]
  const section = parts[1] ?? "";
  const id = parts.slice(2).join("/");
  if (WITH_ID[section]) return id ? { name: WITH_ID[section], id } : { name: section, id: null };
  if (WITHOUT_ID[section]) return { name: WITHOUT_ID[section], id: null };
  return { name: "words", id: null };
}

export const hrefFor = (section, id = null) => (id ? `#/${section}/${id}` : `#/${section}`);
