import { test } from "node:test";
import assert from "node:assert/strict";
import { blockNodes } from "../src/render/blocks.js";
import { t } from "../src/strings.js";
import { assertTextOnly, tags, texts, walk } from "./helpers.js";

const chart = (over) => blockNodes([{ type: "chart", style: "bar", labels: ["a", "b", "c"], series: [{ name: "n", values: [1, 2, 3] }], ...over }], t)[0];
const rects = (node) => { const out = []; walk(node, (n) => n.tag === "rect" && out.push(n)); return out; };

test("a bar chart has one rect per value, with the value in its title and the numbers in a table", () => {
  const node = chart();
  assert.equal(rects(node).length, 3);
  const titles = []; walk(node, (n) => n.tag === "title" && titles.push(texts(n)[0]));
  assert.deepEqual(titles, ["a 1", "b 2", "c 3"]);
  assert.ok(tags(node).includes("table"));
  assertTextOnly(node, "chart");
});

test("unequal label and value counts, an empty series and NaN values still render", () => {
  assert.equal(rects(chart({ labels: ["a"] })).length, 3, "more values than labels");
  assert.equal(rects(chart({ labels: ["a", "b", "c", "d", "e"] })).length, 3, "more labels than values");
  assert.equal(rects(chart({ series: [] })).length, 0);
  assert.ok(texts(chart({ series: [] })).includes("No data"));
  const bad = chart({ series: [{ values: [Number.NaN, Infinity, "x", null, 4] }] });
  for (const r of rects(bad)) for (const key of ["x", "y", "width", "height"]) assert.ok(Number.isFinite(Number(r.attrs[key])), `${key}=${r.attrs[key]}`);
});

test("a line chart is one path built from numbers", () => {
  const node = chart({ style: "line" });
  const paths = []; walk(node, (n) => n.tag === "path" && paths.push(n));
  assert.equal(paths.length, 1);
  assert.match(paths[0].attrs.d, /^M[\d. -]+(L[\d. -]+)*$/);
});

test("no block ever carries an inline style or an event attribute", () => {
  const all = [{ type: "chart", labels: ["x"], series: [{ values: [1] }] }, { type: "stats", tiles: [{ label: "a", value: "b" }] }, { type: "table", columns: [{ title: "a" }], rows: [["b"]] }, { type: "timeline", events: [{ date: "1", title: "t" }] }];
  for (const n of blockNodes(all, t)) walk(n, (x) => { for (const name of Object.keys(x.attrs ?? {})) assert.ok(name !== "style" && !/^on/i.test(name), name); });
});
