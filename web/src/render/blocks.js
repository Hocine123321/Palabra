// Blocks from the phone as element trees: the spec blocks of an artifact and the blocks of a lesson page share this file.
// Everything is text nodes; a block the page does not know shows its text (or its type name) as a plain paragraph.
import { h } from "../view.js";
import { arr, inline, isObject, str } from "./util.js";

const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const para = (text) => h("p", { class: "block-text", dir: "auto" }, inline(text));
const titleLine = (title) => (str(title) ? h("h3", { class: "block-title", dir: "auto" }, inline(title)) : null);

function heading(b) {
  const level = Math.min(3, Math.max(1, Math.round(num(b.level)) || 2));
  return h(`h${level + 1}`, { class: "block-heading", dir: "auto" }, inline(b.text));
}

function list(b) {
  const items = arr(b.items).map((item) => h("li", { dir: "auto" }, inline(item)));
  return h("div", { class: "block" }, titleLine(b.title), h(b.ordered === true ? "ol" : "ul", { class: "block-list" }, ...items));
}

function table(b) {
  const columns = arr(b.columns).map((c) => (isObject(c) ? str(c.title) : str(c)));
  const rows = arr(b.rows).map((row) => arr(row).map((cell) => str(cell)));
  return h(
    "div",
    { class: "table-wrap" },
    h(
      "table",
      { class: "block-table" },
      h("thead", {}, h("tr", {}, ...columns.map((c) => h("th", { scope: "col", dir: "auto" }, c)))),
      h("tbody", {}, ...rows.map((row) => h("tr", {}, ...row.map((cell) => h("td", { dir: "auto" }, cell))))),
    ),
  );
}

/** Bars (or a line) drawn from numbers only; every value is also in a <title> and in the table under the picture. */
function chart(b, tr, lang) {
  const labels = arr(b.labels).map(str);
  const series = arr(b.series).filter(isObject).map((s) => ({ name: str(s.name), values: arr(s.values).map(num) }));
  const first = series[0]?.values ?? [];
  const count = first.length;
  const top = Math.max(1, ...first.map((v) => Math.abs(v)));
  const width = count ? 100 / count : 100;
  const drawn =
    count === 0
      ? null
      : b.style === "line"
        ? h("path", { class: "chart-line", d: first.map((v, i) => `${i ? "L" : "M"}${(i * width + width / 2).toFixed(2)} ${(38 - (Math.max(0, v) / top) * 36).toFixed(2)}`).join(" ") })
        : first.map((v, i) => {
            const height = (Math.max(0, v) / top) * 36;
            return h("rect", { class: "chart-bar", x: (i * width + width * 0.1).toFixed(2), y: (38 - height).toFixed(2), width: (width * 0.8).toFixed(2), height: height.toFixed(2) }, h("title", {}, `${labels[i] ?? ""} ${v}`));
          });
  const header = [h("th", { scope: "col" }, "")].concat(series.map((s) => h("th", { scope: "col", dir: "auto" }, s.name)));
  const body = Array.from({ length: Math.max(labels.length, ...series.map((s) => s.values.length), 0) }, (_, i) =>
    h("tr", {}, h("th", { scope: "row", dir: "auto" }, labels[i] ?? ""), ...series.map((s) => h("td", {}, i < s.values.length ? String(s.values[i]) : ""))),
  );
  return h(
    "figure",
    { class: "chart" },
    str(b.title) ? h("figcaption", { dir: "auto" }, b.title) : null,
    count ? h("svg", { class: "chart-svg", viewBox: "0 0 100 40", role: "img", "aria-label": tr("Chart", lang) }, drawn) : h("p", { class: "secondary" }, tr("No data", lang)),
    body.length ? h("table", { class: "block-table chart-values" }, h("thead", {}, h("tr", {}, ...header)), h("tbody", {}, ...body)) : null,
  );
}

function stats(b) {
  const tiles = arr(b.tiles ?? b.stats).filter(isObject);
  return h(
    "div",
    { class: "block" },
    titleLine(b.title),
    h(
      "div",
      { class: "stat-tiles" },
      ...tiles.map((tile) =>
        h(
          "div",
          { class: "stat-tile" },
          h("span", { class: "stat-value", dir: "auto" }, `${inline(tile.value)}${str(tile.unit) ? ` ${str(tile.unit)}` : ""}`),
          h("span", { class: "stat-label", dir: "auto" }, inline(tile.label)),
          str(tile.note) ? h("span", { class: "secondary", dir: "auto" }, inline(tile.note)) : null,
        ),
      ),
    ),
  );
}

const steps = (items, ordered = true) =>
  h(ordered ? "ol" : "ul", { class: "steps" }, ...arr(items).filter(isObject).map((s) => h("li", {}, h("strong", { dir: "auto" }, inline(s.title)), str(s.detail) ? h("span", { class: "secondary", dir: "auto" }, ` ${inline(s.detail)}`) : null)));

function render(block, tr, lang, depth) {
  if (!isObject(block)) return typeof block === "string" ? para(block) : null;
  const type = str(block.type);
  switch (type) {
    case "heading":
      return heading(block);
    case "text":
    case "paragraph":
      return para(block.text);
    case "list":
      return list(block);
    case "table":
      return table(block);
    case "chart":
      return chart(block, tr, lang);
    case "stats":
      return stats(block);
    case "checklist":
      return h("ul", { class: "block-list checklist" }, ...arr(block.items).map((item) => h("li", { dir: "auto" }, `☐ ${str(item)}`)));
    case "roadmap":
      return steps(block.steps);
    case "process":
      return h("div", { class: "block" }, titleLine(block.title), steps(block.steps));
    case "keyPoint":
      return h("aside", { class: "key-point" }, str(block.label) ? h("strong", { dir: "auto" }, inline(block.label)) : null, para(block.text));
    case "quote":
      return h("blockquote", { class: "quote", dir: "auto" }, inline(block.text), str(block.source) ? h("cite", {}, inline(block.source)) : null);
    case "timeline":
      return h(
        "div",
        { class: "block" },
        titleLine(block.title),
        h("ol", { class: "timeline" }, ...arr(block.events).filter(isObject).map((e) => h("li", {}, h("strong", { dir: "auto" }, inline(e.date)), h("span", { dir: "auto" }, ` ${inline(e.title)}`), str(e.detail) ? h("span", { class: "secondary", dir: "auto" }, ` ${inline(e.detail)}`) : null))),
      );
    case "comparison": {
      const columns = arr(block.columns).map(str);
      return h(
        "div",
        { class: "table-wrap" },
        titleLine(block.title),
        h(
          "table",
          { class: "block-table" },
          h("thead", {}, h("tr", {}, h("th", { scope: "col", dir: "auto" }, inline(block.corner)), ...columns.map((c) => h("th", { scope: "col", dir: "auto" }, inline(c))))),
          h("tbody", {}, ...arr(block.rows).filter(isObject).map((r) => h("tr", {}, h("th", { scope: "row", dir: "auto" }, inline(r.label)), ...arr(r.cells).map((c) => h("td", { dir: "auto" }, inline(c)))))),
        ),
      );
    }
    case "causeEffect":
      return h(
        "div",
        { class: "block" },
        titleLine(block.title),
        h("ol", { class: "steps" }, ...arr(block.stages).filter(isObject).map((s) => h("li", {}, str(s.label) ? h("strong", { dir: "auto" }, `${inline(s.label)}: `) : null, h("span", { dir: "auto" }, arr(s.nodes).map(inline).join(", "))))),
      );
    case "definitions":
      return h("div", { class: "block" }, titleLine(block.title), h("dl", { class: "definitions" }, ...arr(block.definitions ?? block.items).filter(isObject).flatMap((d) => [h("dt", { dir: "auto" }, inline(d.term)), h("dd", { dir: "auto" }, inline(d.definition))])));
    case "image":
      return h("figure", { class: "image-note" }, h("p", { dir: "auto" }, `[${tr("Image", lang)}] ${str(block.alt)}`), str(block.caption) ? h("figcaption", { dir: "auto" }, inline(block.caption)) : null);
    case "columns":
      return depth > 8 ? null : h("div", { class: "columns" }, ...nodes(block.children, tr, lang, depth + 1).map((n) => h("div", { class: "column" }, n)));
    case "section":
      return depth > 8 ? null : h("section", { class: "block-section" }, titleLine(block.title), ...nodes(block.children, tr, lang, depth + 1));
    case "error":
      return h("p", { class: "status", role: "status" }, tr(str(block.message) || "Couldn't load data", lang));
    default:
      return para(str(block.text) || type);
  }
}

function nodes(blocks, tr, lang, depth) {
  return arr(blocks).map((b) => render(b, tr, lang, depth)).filter(Boolean);
}

/** Blocks (anything: not an array gives no nodes) -> nodes. Never throws. */
export function blockNodes(blocks, tr, lang = "en") {
  try {
    return nodes(blocks, tr, lang, 0);
  } catch {
    return [h("p", { class: "status" }, tr("This page can't be shown here", lang))];
  }
}
