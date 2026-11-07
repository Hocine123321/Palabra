import test from "node:test";
import assert from "node:assert/strict";
import { renderArtifactList, renderArtifactPage, MAX_DEPTH, MAX_BLOCKS } from "../src/ui/artifacts.js";
import { makeT } from "../src/ui/strings.js";

const EVIL = '<img src=x onerror=alert(1)>"\'&';
const page = (blocks, title = "T") => ({ id: "1", title, blocks });
const html = (blocks) => renderArtifactPage(page(blocks));

test("every kind of block draws, and text from the phone is shown as text", () => {
  const out = html([
    { type: "heading", level: 1, text: EVIL }, { type: "text", text: EVIL }, { type: "note", text: EVIL },
    { type: "list", ordered: true, items: [EVIL] }, { type: "list", ordered: false, items: [EVIL] },
    { type: "table", columns: [EVIL], rows: [[EVIL]] },
    { type: "stats", tiles: [{ label: EVIL, value: EVIL }] },
    { type: "checklist", items: [{ text: EVIL, done: true }, { text: "b", done: false }] },
    { type: "roadmap", steps: [{ title: EVIL, detail: EVIL, done: false }] },
    { type: "chart", title: EVIL, labels: [EVIL], series: [{ values: [3, 6] }] },
    { type: "section", title: EVIL, children: [{ type: "text", text: EVIL }] },
    { type: "columns", children: [{ type: "text", text: EVIL }] },
  ]);
  assert.doesNotMatch(out, /<img/i);
  assert.doesNotMatch(out, /onerror=alert\(1\)>/);
  for (const tag of ["<h3>", "<ol>", "<ul>", "<table>", "<thead>", 'class="summary"', 'class="check"', 'class="roadmap"', 'class="chart"', "<section>", 'class="cols"']) assert.match(out, new RegExp(tag.replace(/[<>]/g, (c) => `\\${c}`)), tag);
  assert.match(html([{ type: "text", text: "a & b" }]), /a &amp; b/);
});

test("a title with markup is escaped too", () => {
  assert.doesNotMatch(renderArtifactPage(page([], EVIL)), /<img/i);
});

test("a heading level is clamped so it never makes a stray tag", () => {
  for (const level of [0, -4, 9, "x", null, 1.5]) assert.match(html([{ type: "heading", level, text: "h" }]), /<h[345]>h<\/h[345]>/, String(level));
});

test("an unknown or malformed block draws nothing and does not break the rest", () => {
  const out = html([{ type: "script", text: "<script>alert(1)</script>" }, null, 7, "x", {}, { type: "text", text: "kept" }]);
  assert.doesNotMatch(out, /script/i);
  assert.match(out, /<p>kept<\/p>/);
});

test("nesting is cut off at the page's own depth limit, whatever the phone sent", () => {
  let tree = { type: "text", text: "deep" };
  for (let i = 0; i < MAX_DEPTH + 3; i++) tree = { type: "section", title: `s${i}`, children: [tree] };
  const out = html([tree]);
  assert.doesNotMatch(out, /deep/);
  assert.equal((out.match(/<section>/g) ?? []).length, MAX_DEPTH);
});

test("the number of blocks is capped on the page as well", () => {
  const many = Array.from({ length: MAX_BLOCKS + 40 }, (_, i) => ({ type: "text", text: `b${i}` }));
  assert.equal((html(many).match(/<p>/g) ?? []).length, MAX_BLOCKS);
});

test("junk where lists are expected does not throw", () => {
  assert.doesNotThrow(() => html([{ type: "table", columns: "x", rows: 5 }, { type: "list", items: null }, { type: "stats" }, { type: "chart", series: "z" }, { type: "section", children: 4 }]));
  assert.match(html([{ type: "chart", series: [{ values: ["a", NaN] }] }]), /No data to chart/);
});

test("chart bars are scaled to the biggest value and use the label as a tooltip", () => {
  const out = html([{ type: "chart", labels: ["a", "b"], series: [{ values: [5, 10] }] }]);
  assert.match(out, /height:50%/); assert.match(out, /height:100%/); assert.match(out, /title="b: 10"/);
});

test("a bad page shows a calm message, not an error", () => {
  for (const bad of [null, undefined, {}, { blocks: "x" }]) assert.match(renderArtifactPage(bad), /could not be shown/);
});

test("the list opens pages and marks phone-only apps, escaping ids and titles, in English and Arabic", () => {
  const items = [{ id: '"><x>', title: EVIL, viewable: true }, { id: "2", title: "Game", viewable: false }];
  const out = renderArtifactList(items);
  assert.doesNotMatch(out, /<img/i); assert.doesNotMatch(out, /<x>/);
  assert.match(out, /data-artifact="/); assert.match(out, /Opens on your phone/);
  assert.match(renderArtifactList(items, makeT("ar")), /يُفتح على هاتفك/);
  assert.match(renderArtifactList([]), /No artifacts yet/); assert.match(renderArtifactList(null, makeT("ar")), /لا توجد منتجات بعد/);
});
