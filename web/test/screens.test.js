import { test } from "node:test";
import assert from "node:assert/strict";
import { navBar } from "../src/nav.js";
import { blockNodes } from "../src/render/blocks.js";
import { wordDetail } from "../src/render/word.js";
import { buildModel, routedScreen } from "../src/screens.js";
import { t } from "../src/strings.js";

export const MARKUP = "<img src=x onerror=alert(1)>";

export function walk(node, fn) {
  fn(node);
  for (const c of node.children ?? []) if (typeof c !== "string") walk(c, fn);
}
export const texts = (tree) => { const out = []; walk(tree, (n) => n.children?.forEach((c) => typeof c === "string" && out.push(c))); return out; };
export const tags = (tree) => { const out = []; walk(tree, (n) => out.push(n.tag)); return out; };
/** Text nodes only: no element named img/script/iframe/svg-script anywhere, no handler or style anywhere, no attribute carrying the markup. */
export function assertTextOnly(tree, where) {
  walk(tree, (n) => {
    assert.ok(!["img", "script", "iframe", "object", "embed"].includes(n.tag), `${where}: <${n.tag}>`);
    for (const [name, value] of Object.entries(n.attrs ?? {})) {
      assert.ok(!/^on/i.test(name) && name !== "style" && name !== "innerHTML", `${where}: attribute ${name}`);
      assert.ok(!String(value).includes("onerror"), `${where}: attribute ${name} carries data`);
    }
    assert.deepEqual(Object.keys(n.handlers ?? {}).filter((k) => k !== "click"), [], `${where}: handlers`);
  });
}

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
