import test from "node:test";
import assert from "node:assert/strict";
import { tintIndex, libraryView, studyView, activityView, syncedText } from "../src/ui/model.js";

const words = [
  { id: "1", key: "hola", spanish: "hola", translation: "hello", category: "Greetings", tags: ["basic"], createdAt: "2026-11-03T00:00:00Z" },
  { id: "2", key: "gato", spanish: "gato", translation: "cat", category: null, tags: [], createdAt: "2026-11-02T00:00:00Z" },
  { id: "3", key: "adiós", spanish: "adiós", translation: "goodbye", category: "Greetings", tags: ["Basic", "farewell"], createdAt: "2026-11-01T00:00:00Z" },
  { id: "4", key: "mañana", spanish: "mañana", translation: "tomorrow", category: "Time", tags: [], createdAt: "2026-10-30T00:00:00Z" },
];

test("tile tints match the app's FNV-1a hash (reference values computed independently, accents included)", () => {
  const ref = { hola: 5, gato: 2, "niño": 5, a: 4, "": 1, "adiós": 4, "mañana": 3 };
  for (const [k, v] of Object.entries(ref)) assert.equal(tintIndex(k), v, JSON.stringify(k));
});

test("library groups by section in first-seen order with unsectioned last, and keeps the phone's order inside", () => {
  const v = libraryView({ words });
  assert.deepEqual(v.groups.map((g) => g.name), ["Greetings", "Time", null]);
  assert.deepEqual(v.groups[0].words.map((w) => w.spanish), ["hola", "adiós"]);
  assert.equal(v.total, 4); assert.equal(v.shown, 4); assert.equal(v.groups[0].words[0].tint, 5);
});

test("search ignores case and accents and looks in word, translation, section and tags", () => {
  const find = (query) => libraryView({ words }, { query }).groups.flatMap((g) => g.words.map((w) => w.spanish));
  assert.deepEqual(find("ADIOS"), ["adiós"]);
  assert.deepEqual(find("manana"), ["mañana"]);
  assert.deepEqual(find("cat"), ["gato"]);
  assert.deepEqual(find("greet"), ["hola", "adiós"]);
  assert.deepEqual(find("farewell"), ["adiós"]);
  assert.deepEqual(find("  "), ["hola", "adiós", "mañana", "gato"]);
});

test("tag and section filters narrow the list; tags are case-insensitive and de-duplicated by exact text", () => {
  assert.deepEqual(libraryView({ words }, { tag: "basic" }).groups.flatMap((g) => g.words.map((w) => w.spanish)), ["hola", "adiós"]);
  assert.deepEqual(libraryView({ words }, { section: "Time" }).groups.flatMap((g) => g.words.map((w) => w.spanish)), ["mañana"]);
  assert.deepEqual(libraryView({ words }, { section: null }).groups.flatMap((g) => g.words.map((w) => w.spanish)), ["gato"]); // only the unsectioned
});

test("empty library and no-match states are told apart", () => {
  assert.equal(libraryView({ words: [] }).isEmpty, true);
  assert.equal(libraryView({}).isEmpty, true);
  const none = libraryView({ words }, { query: "zzz" });
  assert.equal(none.noMatches, true); assert.equal(none.isEmpty, false);
});

test("study view totals due and new, and lists the weakest review words first", () => {
  const v = studyView({
    decks: [{ id: "a", name: "Vocabulary", kind: "vocabulary", total: 10, due: 3, new: 2 }, { id: "b", name: "Verbs", kind: "user", total: 5, due: 1, new: 0 }],
    review: [{ wordID: "x", headword: "b", score: 0.9 }, { wordID: "y", headword: "a", score: 0.2 }],
  });
  assert.equal(v.dueTotal, 4); assert.equal(v.newTotal, 2);
  assert.deepEqual(v.review.map((r) => r.headword), ["a", "b"]);
  assert.equal(studyView({}).hasDecks, false); assert.equal(studyView({}).hasReview, false);
});

test("activity bars scale to the busiest day and never divide by zero", () => {
  const v = activityView({ wordsPerDay: [{ day: "2026-11-05", count: 2 }, { day: "2026-11-06", count: 4 }, { day: "2026-11-07", count: 0 }] });
  assert.deepEqual(v.days.map((d) => d.height), [50, 100, 0]); assert.equal(v.total, 6);
  assert.deepEqual(activityView({ wordsPerDay: [{ day: "d", count: 0 }] }).days.map((d) => d.height), [0]);
});

test("sync text", () => {
  const now = new Date("2026-11-07T12:00:00Z");
  assert.equal(syncedText(null, now), "Not synced yet");
  assert.equal(syncedText("2026-11-07T11:59:40Z", now), "Synced just now");
  assert.equal(syncedText("2026-11-07T11:50:00Z", now), "Synced 10 min ago");
  assert.equal(syncedText("2026-11-07T09:00:00Z", now), "Synced 3 h ago");
  assert.equal(syncedText("2026-11-05T12:00:00Z", now), "Synced 2 d ago");
});
