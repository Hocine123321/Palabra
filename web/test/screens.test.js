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
