import { test } from "node:test";
import assert from "node:assert/strict";
import { confirmScreen, h, mount, pairScreen, removedScreen, wordsScreen } from "../src/view.js";
import { KEYS, dirFor, pickLang, t } from "../src/strings.js";

function walk(node, fn) {
  fn(node);
  for (const c of node.children ?? []) if (typeof c !== "string") walk(c, fn);
}
const texts = (tree) => { const out = []; walk(tree, (n) => n.children?.forEach((c) => typeof c === "string" && out.push(c))); return out; };

const words = [
  { id: "1", spanish: "<img src=x onerror=alert(1)>", translation: "tomorrow", category: "Time", tags: ["a", "b"] },
  { id: "2", spanish: "mañana", translation: "morning", category: null, tags: [] },
  { id: "3", spanish: "مرحبا", translation: "hello", category: "Greetings", tags: ["x"] },
];

test("word text stays text: no markup, no handlers or data in attributes", () => {
  const tree = wordsScreen({ words, syncedAt: 1_700_000_000_000, lang: "en" });
  assert.ok(texts(tree).includes("<img src=x onerror=alert(1)>"), "the markup is just a string child");
  walk(tree, (n) => {
    for (const [name, value] of Object.entries(n.attrs ?? {})) {
      assert.ok(!/^on/i.test(name) && name !== "innerHTML" && name !== "style", `attribute ${name}`);
      assert.equal(typeof value, "string");
      assert.ok(!value.includes("onerror"), "no word data inside attributes");
    }
  });
});

test("three words make three rows with spanish, translation, category and tags", () => {
  const tree = wordsScreen({ words, syncedAt: null, lang: "en" });
  const rows = [];
  walk(tree, (n) => n.tag === "li" && rows.push(n));
  assert.equal(rows.length, 3);
  const first = rows.flatMap((r) => { const o = []; walk(r, (n) => n.children?.forEach((c) => typeof c === "string" && o.push(c))); return o; });
  for (const expected of ["tomorrow", "Time", "a", "b", "mañana", "مرحبا", "Greetings"]) assert.ok(first.includes(expected), expected);
});

test("an empty list shows the empty-state text", () => {
  const tree = wordsScreen({ words: [], syncedAt: null, lang: "en" });
  assert.ok(texts(tree).includes(t("No words yet. Add words in the Palabra app on your phone.", "en")));
  let lis = 0;
  walk(tree, (n) => n.tag === "li" && lis++);
  assert.equal(lis, 0);
});

test("language and direction", () => {
  assert.equal(pickLang("ar-DZ"), "ar");
  assert.equal(pickLang("en-US"), "en");
  assert.equal(pickLang(""), "en");
  assert.equal(dirFor("ar"), "rtl");
  assert.equal(dirFor("en"), "ltr");
});

test("every string a screen uses has an Arabic translation", () => {
  const used = new Set();
  const tr = (key, lang) => { used.add(key); return t(key, lang); };
  const noop = () => {};
  pairScreen({ link: "https://x.test/#p=1", status: "waiting", lang: "ar", onCancel: noop, onRestart: noop }, tr);
  for (const status of ["expired", "cancelled", "error"]) pairScreen({ link: "https://x.test/#p=1", status, lang: "ar", onCancel: noop, onRestart: noop }, tr);
  confirmScreen({ code: "1234", lang: "ar", waiting: false, onMatch: noop, onCancel: noop }, tr);
  confirmScreen({ code: "1234", lang: "ar", waiting: true, onMatch: noop, onCancel: noop }, tr);
  for (const status of [null, "offline", "error", "syncing"]) wordsScreen({ words, syncedAt: 1, status, lang: "ar", onRefresh: noop }, tr);
  wordsScreen({ words: [], syncedAt: null, lang: "ar", onRefresh: noop }, tr);
  removedScreen({ lang: "ar", onPairAgain: noop }, tr);
  assert.ok(used.size > 10);
  for (const key of used) {
    assert.ok(KEYS[key], `"${key}" is registered`);
    assert.ok(KEYS[key].length > 0 && KEYS[key] !== key, `"${key}" has an Arabic translation`);
  }
});

test("the pair screen carries the QR as an svg tree and a Cancel button", () => {
  const tree = pairScreen({ link: "https://x.test/#p=1", status: "waiting", lang: "en", onCancel: () => {}, onRestart: () => {} });
  const tags = [];
  walk(tree, (n) => tags.push(n.tag));
  assert.ok(tags.includes("svg") && tags.includes("button"));
});

test("handlers are kept apart from attributes", () => {
  const fn = () => {};
  const node = h("button", { class: "a", onClick: fn }, "x");
  assert.deepEqual(node.attrs, { class: "a" });
  assert.equal(node.handlers.click, fn);
});

test("mount builds elements with textContent only and sets text, not markup", () => {
  const made = [];
  const doc = {
    createElement: (tag) => { const el = { tag, attrs: {}, kids: [], setAttribute(k, v) { this.attrs[k] = v; }, append(c) { this.kids.push(c); }, addEventListener(type, fn) { this.attrs[`@${type}`] = fn; } }; made.push(el); return el; },
    createElementNS: (ns, tag) => doc.createElement(tag),
    createTextNode: (text) => ({ text }),
  };
  const root = { replaceChildren(...kids) { this.kids = kids; } };
  mount(root, h("p", { class: "x" }, "<b>hi</b>"), doc);
  assert.equal(root.kids.length, 1);
  assert.equal(root.kids[0].kids[0].text, "<b>hi</b>");
  assert.equal(root.kids[0].attrs.class, "x");
});
