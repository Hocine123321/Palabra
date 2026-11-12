// Words flagged as needing review, newest change first, as the phone sent them.
import { h, screenFrame } from "../view.js";
import { arr, isObject, parseTime, str } from "./util.js";

export function reviewScreen({ needs, words, lang, frame = {} }, tr) {
  const known = new Map(arr(words).filter(isObject).map((w) => [w.recordId, w.id]));
  const sorted = arr(needs).filter(isObject).sort((a, b) => (parseTime(b.updatedAt) ?? 0) - (parseTime(a.updatedAt) ?? 0));
  const rows = sorted.map((need) => {
    const itemId = known.get(need.wordId);
    const flags = Number.isFinite(need.flagCount) ? need.flagCount : 0;
    return h(
      "li",
      { class: "row" },
      itemId ? h("a", { class: "headword", dir: "auto", href: `#/words/${itemId}` }, str(need.headword)) : h("span", { class: "headword", dir: "auto" }, str(need.headword)),
      h("span", { class: "translation", dir: "auto" }, str(need.translation)),
      str(need.note) ? h("span", { dir: "auto" }, need.note) : null,
      flags > 0 ? h("span", { class: "category" }, `${tr("Flagged", lang)}: ${Math.round(flags)}`) : null,
    );
  });
  return screenFrame({ ...frame, title: tr("Need Review", lang), lang }, tr, rows.length ? h("ul", { class: "list" }, ...rows) : h("p", { class: "empty" }, tr("Nothing here yet", lang)));
}
