import { test } from "node:test";
import assert from "node:assert/strict";
import { navBar } from "../src/nav.js";
import { blockNodes } from "../src/render/blocks.js";
import { wordDetail } from "../src/render/word.js";
import { buildModel, routedScreen } from "../src/screens.js";
import { t } from "../src/strings.js";

import { MARKUP, assertTextOnly, tags, texts, walk } from "./helpers.js";

const frame = { syncedAt: null, status: null, freshness: undefined, onRefresh: () => {}, now: () => 0 };

test("a word with markup in every text field is rendered as text only", () => {
  const word = {
    id: "i1", spanish: MARKUP, translation: MARKUP, partOfSpeech: MARKUP, category: MARKUP, tags: [MARKUP],
    content: {
      word: MARKUP,
      examples: [{ context: MARKUP, spanish: MARKUP, translation: MARKUP }],
      meaning: { translations: [MARKUP], explanation: MARKUP },
      usage: { explanation: MARKUP, register: MARKUP, nuance: MARKUP },
      forms: { partOfSpeech: MARKUP, groups: [{ label: MARKUP, items: [{ form: MARKUP, note: MARKUP }] }] },
      similarWords: [{ word: MARKUP, difference: MARKUP }],
      somethingNew: { a: MARKUP, b: [MARKUP] },
    },
  };
  const tree = wordDetail({ word, lang: "en", frame }, t);
  assertTextOnly(tree, "wordDetail");
  assert.ok(texts(tree).includes(MARKUP));
  const all = texts(tree).join("|");
  for (const heading of ["Examples", "Meaning", "Usage and register", "Forms", "Similar words", "somethingNew"]) assert.ok(all.includes(heading), heading);
  assert.ok(texts(tree).some((s) => s.includes("a: " + MARKUP)), "an unknown section shows as plain lines");
});

test("a word with content missing, null, text or numbers does not throw", () => {
  for (const content of [undefined, null, "just text", [1, 2, 3], 42, true, {}, { examples: "nope", meaning: 5, usage: [], forms: null, similarWords: {} }]) {
    const tree = wordDetail({ word: { id: "i", spanish: "hola", translation: "hello", content }, lang: "en", frame }, t);
    assert.ok(texts(tree).includes("hello"));
  }
  assert.ok(texts(wordDetail({ word: { id: "i" }, lang: "en", frame }, t)).length > 0);
});

test("a word that is gone says so and links back", () => {
  const tree = wordDetail({ word: null, lang: "en", frame }, t);
  assert.ok(texts(tree).includes("That item is gone"));
  let link = null;
  walk(tree, (n) => { if (n.tag === "a" && n.attrs.href === "#/words") link = n; });
  assert.ok(link);
});

test("the navigation bar marks exactly one current link and has Arabic labels", () => {
  for (const [route, current] of [[{ name: "words", id: null }, "#/words"], [{ name: "word", id: "x" }, "#/words"], [{ name: "book", id: "x" }, "#/books"], [{ name: "review", id: null }, "#/review"]]) {
    const bar = navBar({ route, lang: "en" }, t);
    const marked = [];
    walk(bar, (n) => n.attrs?.["aria-current"] && marked.push(n.attrs.href));
    assert.deepEqual(marked, [current], JSON.stringify(route));
  }
  const links = [];
  walk(navBar({ route: { name: "words", id: null }, lang: "ar" }, t), (n) => n.tag === "a" && links.push(texts(n)[0]));
  assert.equal(links.length, 6);
  for (const label of links) assert.match(label, /[؀-ۿ]/, label);
});

test("a count badge only shows for a positive whole number", () => {
  const bar = navBar({ route: { name: "words", id: null }, lang: "en", counts: { words: 3, study: 0, review: -1, chat: "x", books: 2.5 } }, t);
  const badges = [];
  walk(bar, (n) => n.attrs?.class === "count" && badges.push(texts(n)[0]));
  assert.deepEqual(badges, ["3"]);
});

test("blocks of every known type, an unknown type and odd inputs render without throwing", () => {
  const long = "x".repeat(3000);
  const spec = [
    { type: "heading", level: 2, text: MARKUP }, { type: "text", text: long }, { type: "list", ordered: true, items: [MARKUP, 5, null] },
    { type: "table", columns: [{ title: MARKUP }], rows: [[MARKUP], [1, 2]] },
    { type: "chart", style: "bar", title: MARKUP, labels: [MARKUP, "b"], series: [{ name: MARKUP, values: [1, 2] }] },
    { type: "stats", tiles: [{ label: MARKUP, value: MARKUP }] }, { type: "checklist", id: "c", items: [MARKUP] },
    { type: "roadmap", id: "r", steps: [{ title: MARKUP, detail: MARKUP }] },
    { type: "columns", children: [{ type: "text", text: MARKUP }] }, { type: "section", title: MARKUP, children: [{ type: "text", text: MARKUP }] },
    { type: "error", message: "Couldn't load data" },
  ];
  const lesson = [
    { type: "paragraph", text: `${MARKUP} {{term|id}} [[1815|e]] **bold**` }, { type: "keyPoint", label: MARKUP, text: MARKUP }, { type: "quote", text: MARKUP, source: MARKUP },
    { type: "timeline", title: MARKUP, events: [{ date: MARKUP, title: MARKUP, detail: MARKUP }] }, { type: "stats", stats: [{ label: MARKUP, value: MARKUP, unit: MARKUP, note: MARKUP }] },
    { type: "comparison", corner: MARKUP, columns: [MARKUP], rows: [{ label: MARKUP, cells: [MARKUP] }] }, { type: "causeEffect", stages: [{ label: MARKUP, nodes: [MARKUP] }] },
    { type: "process", steps: [{ title: MARKUP, detail: MARKUP }] }, { type: "definitions", definitions: [{ term: MARKUP, definition: MARKUP }] },
    { type: "image", alt: MARKUP, caption: MARKUP }, { type: "hologram" }, { type: "hologram", text: MARKUP },
  ];
  for (const blocks of [spec, lesson]) {
    const nodes = blockNodes(blocks, t, "en");
    assert.equal(nodes.length, blocks.length);
    for (const n of nodes) assertTextOnly(n, "block");
  }
  const inlineText = texts({ children: blockNodes(lesson, t) }).join("|");
  assert.ok(inlineText.includes("term 1815 bold"), "lesson markup keeps its text: " + inlineText.slice(0, 80));
  assert.ok(texts({ children: blockNodes([{ type: "hologram" }], t) }).includes("hologram"), "an unknown type shows its name");
  for (const odd of [null, undefined, "text", 5, {}, [null, 1, "x", [], {}], [{ type: "chart", series: "no", labels: 5 }], [{ type: "chart", series: [{ values: [Number.NaN, "a", null, Infinity] }] }], [{ type: "table", columns: 3, rows: "x" }]]) {
    assert.ok(Array.isArray(blockNodes(odd, t)), JSON.stringify(odd));
  }
  assert.deepEqual(blockNodes(null, t), []);
});

test("columns and sections nested deeper than eight levels stop instead of recursing forever", () => {
  let block = { type: "text", text: "leaf" };
  for (let i = 0; i < 50; i++) block = { type: "section", title: "s", children: [block] };
  assert.ok(blockNodes([block], t).length === 1);
});

test("the model groups rows by kind, keeps the item id for links and sorts words newest first", () => {
  const model = buildModel([
    { id: "i1", kind: "word", recordId: "uuid-1", d: { id: "uuid-1", spanish: "a", createdAt: "2026-01-01T00:00:00Z" } },
    { id: "i2", kind: "word", recordId: "uuid-2", d: { id: "uuid-2", spanish: "b", createdAt: "2026-02-01T00:00:00Z" } },
    { id: "i3", kind: "stats", recordId: "stats", d: { streak: 2 } },
    { id: "i4", kind: "unknown", recordId: "x", d: {} },
    null, { kind: 5 },
  ]);
  assert.deepEqual(model.words.map((w) => w.id), ["i2", "i1"], "links use the item id, not the phone's uuid");
  assert.equal(model.words[0].recordId, "uuid-2");
  assert.equal(model.stats.streak, 2);
  assert.deepEqual(buildModel(null).words, []);
});

test("the routed screen opens the right word and shows the navigation", () => {
  const model = buildModel([{ id: "i1", kind: "word", recordId: "u", d: { spanish: "hola", translation: "hello" } }]);
  const open = routedScreen({ route: { name: "word", id: "i1" }, model, frame, lang: "en" }, t);
  assert.ok(texts(open).includes("hello"));
  assert.ok(tags(open).includes("nav"));
  const gone = routedScreen({ route: { name: "word", id: "nope" }, model, frame, lang: "en" }, t);
  assert.ok(texts(gone).includes("That item is gone"));
});

// MARK: Study and Need Review

import { reviewScreen } from "../src/render/review.js";
import { sevenDays, studyScreen } from "../src/render/study.js";

const deck = (over = {}) => ({ id: "di", recordId: "d1", name: "Verbs", kind: "user", counts: { total: 5, due: 2, new: 3 }, countsAt: "2026-11-09T21:30:00Z", ...over });

test("decks and cards with markup are text only, with the phone's numbers and time", () => {
  const tree = studyScreen({
    decks: [deck({ name: MARKUP }), deck({ id: "dv", recordId: "dv", name: "Vocabulary", kind: "vocabulary", counts: { total: 9, due: 1, new: 0 } })],
    cards: [{ id: "c1", deckId: "d1", front: MARKUP, back: MARKUP, createdAt: "2026-01-01T00:00:00Z" }, { id: "c2", deckId: "dv", front: "from-words", back: "x" }],
    stats: { reviewedToday: 4, streak: 7, lastSevenDays: [1, 2, 3, 4, 5, 6, 7], asOf: "2026-11-09T21:30:00Z" },
    lang: "en", frame,
  }, t);
  assertTextOnly(tree, "study");
  const all = texts(tree);
  assert.ok(all.includes(MARKUP));
  assert.ok(all.some((s) => s.includes("Total 5 · Due 2 · New 3")), all.join("|"));
  assert.ok(all.some((s) => s.startsWith("As of ") && s.length > 6));
  assert.ok(!all.includes("from-words"), "the vocabulary deck's cards come from the words");
  assert.ok(tags(tree).includes("details"), "a user deck's cards are behind a details element");
  assert.ok(all.includes("7"), "the streak");
  assert.ok(all.includes("1  2  3  4  5  6  7"));
});

test("an unparseable countsAt shows no time and nothing says Invalid Date", () => {
  for (const countsAt of ["nonsense", "", null, 12, undefined]) {
    const all = texts(studyScreen({ decks: [deck({ countsAt })], cards: [], stats: null, lang: "en", frame }, t));
    assert.ok(!all.some((s) => s.includes("As of") || s.includes("Invalid")), String(countsAt));
  }
});

test("a seven-day list of the wrong length or with other types becomes seven zeros", () => {
  const zeros = [0, 0, 0, 0, 0, 0, 0];
  for (const bad of [[1, 2], [1, 2, 3, 4, 5, 6, 7, 8], ["a", 1, 2, 3, 4, 5, 6], [null, 1, 2, 3, 4, 5, 6], "1234567", null, undefined, {}, [-1, 0, 0, 0, 0, 0, 0], [Infinity, 0, 0, 0, 0, 0, 0]]) {
    assert.deepEqual(sevenDays(bad), zeros, JSON.stringify(bad));
  }
  assert.deepEqual(sevenDays([1, 2, 3, 4, 5, 6, 7]), [1, 2, 3, 4, 5, 6, 7]);
  const tree = studyScreen({ decks: [], cards: [], stats: { reviewedToday: "x", streak: -3, lastSevenDays: ["a"] }, lang: "en", frame }, t);
  let rects = 0;
  walk(tree, (n) => n.tag === "rect" && (rects += 1));
  assert.equal(rects, 7);
});

test("empty study collections show the empty line, in Arabic too", () => {
  assert.ok(texts(studyScreen({ decks: [], cards: [], stats: null, lang: "en", frame }, t)).includes("Nothing here yet"));
  assert.ok(texts(studyScreen({ decks: [], cards: [], stats: null, lang: "ar", frame }, t)).includes("لا يوجد شيء هنا بعد"));
  assert.ok(texts(studyScreen({ decks: null, cards: undefined, stats: 5, lang: "en", frame }, t)).length > 0);
});

test("decks are sorted by name", () => {
  const tree = studyScreen({ decks: [deck({ id: "b", recordId: "b", name: "Beta" }), deck({ id: "a", recordId: "a", name: "Alpha" })], cards: [], stats: null, lang: "en", frame }, t);
  const names = [];
  walk(tree, (n) => n.tag === "strong" && names.push(texts(n)[0]));
  assert.deepEqual(names, ["Alpha", "Beta"]);
});

test("needs show their note and flag count, newest first, and link only when the word exists", () => {
  const needs = [
    { id: "n1", wordId: "w-missing", headword: "viejo", translation: "old", note: "x", flagCount: 1, updatedAt: "2026-01-01T00:00:00Z" },
    { id: "n2", wordId: "w1", headword: MARKUP, translation: MARKUP, note: MARKUP, flagCount: 3, score: 0.4, updatedAt: "2026-03-01T00:00:00Z" },
  ];
  const tree = reviewScreen({ needs, words: [{ id: "itemW", recordId: "w1" }], lang: "en", frame }, t);
  assertTextOnly(tree, "review");
  const heads = [];
  walk(tree, (n) => n.attrs?.class === "headword" && heads.push({ tag: n.tag, href: n.attrs.href, text: texts(n)[0] }));
  assert.deepEqual(heads, [{ tag: "a", href: "#/words/itemW", text: MARKUP }, { tag: "span", href: undefined, text: "viejo" }]);
  assert.ok(texts(tree).includes("Flagged: 3"));
  assert.ok(texts(reviewScreen({ needs: [], words: [], lang: "en", frame }, t)).includes("Nothing here yet"));
  assert.ok(texts(reviewScreen({ needs: [{ headword: 5, flagCount: "x", updatedAt: {} }, null, "x"], words: null, lang: "en", frame }, t)).length > 0);
});

test("the routed screen shows Study and Need Review from the model", () => {
  const model = buildModel([
    { id: "i1", kind: "deck", recordId: "d1", d: { name: "Verbs", kind: "user", counts: { total: 1, due: 0, new: 1 } } },
    { id: "i2", kind: "review", recordId: "n1", d: { wordId: "x", headword: "viejo", translation: "old", flagCount: 1, updatedAt: "2026-01-01T00:00:00Z" } },
  ]);
  assert.ok(texts(routedScreen({ route: { name: "study", id: null }, model, frame, lang: "en" }, t)).includes("Verbs"));
  assert.ok(texts(routedScreen({ route: { name: "review", id: null }, model, frame, lang: "en" }, t)).includes("viejo"));
});

// MARK: Artifacts, Chat and Books

import { artifactList, artifactScreen } from "../src/render/artifacts.js";
import { bookReader, booksScreen, dirOfLanguage } from "../src/render/books.js";
import { chatScreen } from "../src/render/chat.js";

test("the artifact list puts spec pages first and offers apps only as 'open on your phone'", () => {
  const tree = artifactList({ artifacts: [
    { id: "a1", kind: "app", title: "Game", updatedAt: "2026-05-01T00:00:00Z" },
    { id: "s1", kind: "spec", title: MARKUP, updatedAt: "2026-01-01T00:00:00Z" },
  ], lang: "en", frame }, t);
  assertTextOnly(tree, "artifacts");
  const heads = [];
  walk(tree, (n) => n.attrs?.class === "headword" && heads.push({ tag: n.tag, href: n.attrs.href, text: texts(n)[0] }));
  assert.deepEqual(heads, [{ tag: "a", href: "#/artifacts/s1", text: MARKUP }, { tag: "span", href: undefined, text: "Game" }]);
  assert.ok(texts(tree).includes("Open this on your phone"));
  assert.ok(texts(artifactList({ artifacts: [], lang: "en", frame }, t)).includes("Nothing here yet"));
});

test("an artifact page shows its blocks; odd blocks and gone items have their own lines", () => {
  const page = artifactScreen({ artifact: { id: "s1", kind: "spec", title: MARKUP, blocks: [{ type: "text", text: MARKUP }, { type: "table", columns: [{ title: "A" }], rows: [[MARKUP]] }, { type: "checklist", items: [MARKUP] }] }, lang: "en", frame }, t);
  assertTextOnly(page, "artifact");
  assert.ok(texts(page).filter((s) => s === MARKUP || s === `☐ ${MARKUP}`).length >= 4);
  for (const blocks of ["x", null, {}, 5, undefined]) {
    assert.ok(texts(artifactScreen({ artifact: { kind: "spec", title: "t", blocks }, lang: "en", frame }, t)).includes("This page can't be shown here"), String(blocks));
  }
  assert.ok(texts(artifactScreen({ artifact: { kind: "app", title: "G", blocks: null }, lang: "en", frame }, t)).includes("Open this on your phone"));
  assert.ok(texts(artifactScreen({ artifact: null, lang: "en", frame }, t)).includes("That item is gone"));
});

test("chat turns come in order with line breaks as separate nodes and markup as text", () => {
  const chat = { title: MARKUP, turns: [{ role: "user", text: `${MARKUP}\nsecond line`, createdAt: "2026-01-01T00:00:00Z", status: "sent" }, { role: "assistant", text: "مرحبا", status: "failed" }] };
  const tree = chatScreen({ chat, lang: "en", frame }, t);
  assertTextOnly(tree, "chat");
  const all = texts(tree);
  assert.ok(all.indexOf(MARKUP) < all.indexOf("second line") && all.indexOf("second line") < all.indexOf("مرحبا"));
  assert.ok(tags(tree).includes("br"));
  assert.ok(all.some((s) => s.includes("Not sent")));
  assert.ok(Array.isArray(chatScreen({ chat: { turns: [{}] }, lang: "en", frame }, t).children));
  for (const odd of [null, undefined, {}, { turns: "x" }, { turns: [null, 5] }]) {
    assert.ok(texts(chatScreen({ chat: odd, lang: "en", frame }, t)).includes("Nothing here yet"), JSON.stringify(odd));
  }
});

const lesson = (over = {}) => ({ id: "li1", recordId: "les1", title: MARKUP, summary: MARKUP, bookId: "b", bookTitle: MARKUP, chapterId: "c", chapterTitle: MARKUP, language: "ar", pageIds: ["p1", "p2"], terms: { m: { term: MARKUP, definition: MARKUP } }, notes: [MARKUP], ...over });
const page = (n, over = {}) => ({ id: `pg${n}`, lessonId: "les1", number: n, title: `${MARKUP} ${n}`, dateLabel: MARKUP, blocks: [{ type: "paragraph", text: MARKUP }, { type: "hologram" }], ...over });

test("the books list groups by book and chapter and links lessons", () => {
  const tree = booksScreen({ lessons: [lesson(), lesson({ id: "li2", recordId: "les2", title: "Other", chapterId: "c2", chapterTitle: "Unit 2" })], lang: "en", frame }, t);
  assertTextOnly(tree, "books");
  const links = [];
  walk(tree, (n) => n.tag === "a" && n.attrs.class === "headword" && links.push(n.attrs.href));
  assert.deepEqual(links.sort(), ["#/books/li1", "#/books/li2"]);
  assert.ok(texts(booksScreen({ lessons: [], lang: "en", frame }, t)).includes("Nothing here yet"));
});

test("the reader shows pages in number order from one lesson, with markup as text", () => {
  const tree = bookReader({ lesson: lesson(), pages: [page(2), page(1), page(1, { lessonId: "other", id: "x", title: "FOREIGN" })], lang: "en", frame }, t);
  assertTextOnly(tree, "reader");
  const all = texts(tree);
  assert.ok(all.indexOf(`${MARKUP} 1`) < all.indexOf(`${MARKUP} 2`));
  assert.ok(!all.includes("FOREIGN"));
  assert.ok(all.includes("hologram"), "an unknown block shows its type");
  assert.ok(!all.includes("Some pages have not arrived yet"));
  assert.ok(texts(bookReader({ lesson: lesson(), pages: [page(1)], lang: "en", frame }, t)).includes("Some pages have not arrived yet"));
});

test("a lesson with no pages shows its title and the empty line", () => {
  const all = texts(bookReader({ lesson: lesson({ pageIds: [] }), pages: [], lang: "en", frame }, t));
  assert.ok(all.includes(MARKUP) && all.includes("Nothing here yet"));
  assert.ok(texts(bookReader({ lesson: lesson({ pageIds: undefined, terms: 5, notes: "x" }), pages: null, lang: "en", frame }, t)).length > 0);
});

test("the reader's direction follows the lesson's language, not the browser's", () => {
  const rootOf = (tree) => { let found = null; walk(tree, (n) => n.attrs?.class === "reader" && (found = n)); return found; };
  assert.equal(rootOf(bookReader({ lesson: lesson({ language: "ar" }), pages: [], lang: "en", frame }, t)).attrs.dir, "rtl");
  assert.equal(rootOf(bookReader({ lesson: lesson({ language: "en" }), pages: [], lang: "ar", frame }, t)).attrs.dir, "ltr");
  assert.equal(rootOf(bookReader({ lesson: lesson({ language: undefined }), pages: [], lang: "ar", frame }, t)).attrs.dir, "ltr");
  assert.equal(dirOfLanguage("ar-EG"), "rtl");
  assert.equal(dirOfLanguage("HE"), "rtl");
  assert.equal(dirOfLanguage("es"), "ltr");
});

test("a vanished lesson, artifact or word shows 'That item is gone' through the router", () => {
  const model = buildModel([]);
  for (const name of ["word", "artifact", "book"]) {
    assert.ok(texts(routedScreen({ route: { name, id: "nope" }, model, frame, lang: "en" }, t)).includes("That item is gone"), name);
  }
  for (const name of ["words", "study", "review", "artifacts", "chat", "books"]) {
    assert.ok(texts(routedScreen({ route: { name, id: null }, model, frame, lang: "ar" }, t)).length > 0, name);
  }
});
