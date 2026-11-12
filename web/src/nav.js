import { hrefFor } from "./router.js";
import { h } from "./view.js";

const ITEMS = [
  ["words", "Words"],
  ["study", "Study"],
  ["review", "Need Review"],
  ["artifacts", "Artifacts"],
  ["chat", "Chat"],
  ["books", "Books"],
];
const SECTION_OF = { word: "words", artifact: "artifacts", book: "books" };

/** The bar of links at the top of every screen. The current section is marked with aria-current="page". */
export function navBar({ route, lang, counts = {} }, tr) {
  const current = SECTION_OF[route?.name] ?? route?.name;
  return h(
    "nav",
    { class: "nav", "aria-label": tr("Sections", lang) },
    ...ITEMS.map(([section, label]) => {
      const n = counts[section];
      return h(
        "a",
        { class: "nav-link", href: hrefFor(section), "aria-current": section === current ? "page" : null },
        tr(label, lang),
        Number.isInteger(n) && n > 0 ? h("span", { class: "count" }, String(n)) : null,
      );
    }),
  );
}
