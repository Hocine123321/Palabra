// Decks, user cards and study stats exactly as the phone sent them. The page decides nothing: counts and streak are shown
// with the time they were true ("as of"), and the vocabulary deck has no cards here (it is made from the words).
import { h, screenFrame } from "../view.js";
import { arr, formatTime, isObject, parseTime, str } from "./util.js";

const whole = (v) => (Number.isFinite(v) && v >= 0 ? Math.round(v) : 0);
const byName = (a, b) => str(a.name).localeCompare(str(b.name)) || str(a.id).localeCompare(str(b.id));

/** Seven whole numbers, oldest first, or seven zeros when the phone's list is not exactly that. */
export function sevenDays(value) {
  return Array.isArray(value) && value.length === 7 && value.every((v) => Number.isFinite(v) && v >= 0) ? value.map(whole) : Array(7).fill(0);
}

function bars(values) {
  const top = Math.max(1, ...values);
  const width = 100 / values.length;
  return h(
    "svg",
    { class: "chart-svg", viewBox: "0 0 100 40", role: "img", "aria-hidden": "true" },
    ...values.map((v, i) => {
      const height = (v / top) * 36;
      return h("rect", { class: "chart-bar", x: (i * width + width * 0.1).toFixed(2), y: (38 - height).toFixed(2), width: (width * 0.8).toFixed(2), height: height.toFixed(2) }, h("title", {}, String(v)));
    }),
  );
}

const tile = (label, value) => h("div", { class: "stat-tile" }, h("span", { class: "stat-value" }, String(value)), h("span", { class: "stat-label" }, label));

function statsBlock(stats, lang, tr) {
  if (!isObject(stats)) return null;
  const days = sevenDays(stats.lastSevenDays);
  const asOf = parseTime(stats.asOf);
  return h(
    "section",
    { class: "detail-section" },
    h("h2", {}, tr("Progress", lang)),
    h("div", { class: "stat-tiles" }, tile(tr("Reviewed today", lang), whole(stats.reviewedToday)), tile(tr("Day streak", lang), whole(stats.streak))),
    h("figure", { class: "chart" }, h("figcaption", {}, tr("Last 7 days", lang)), bars(days), h("p", { class: "secondary day-values" }, days.join("  "))),
    asOf !== null ? h("p", { class: "secondary" }, `${tr("As of", lang)} ${formatTime(asOf, lang)}`) : null,
  );
}

function deckBlock(deck, cards, lang, tr) {
  const counts = isObject(deck.counts) ? deck.counts : {};
  const at = parseTime(deck.countsAt);
  const summary = h("span", { class: "deck-line" }, h("strong", { dir: "auto" }, str(deck.name)), h("span", { class: "secondary" }, ` ${tr("Total", lang)} ${whole(counts.total)} · ${tr("Due", lang)} ${whole(counts.due)} · ${tr("New", lang)} ${whole(counts.new)}`));
  const mine = deck.kind === "user" ? cards.filter((c) => c.deckId === deck.recordId).sort((a, b) => (parseTime(a.createdAt) ?? 0) - (parseTime(b.createdAt) ?? 0)) : [];
  return h(
    "li",
    { class: "row deck" },
    mine.length
      ? h("details", {}, h("summary", {}, summary), h("ul", { class: "cards" }, ...mine.map((c) => h("li", {}, h("span", { class: "spanish", dir: "auto" }, str(c.front)), h("span", { class: "translation", dir: "auto" }, ` ${str(c.back)}`)))))
      : summary,
    at !== null ? h("span", { class: "secondary" }, `${tr("As of", lang)} ${formatTime(at, lang)}`) : null,
  );
}

export function studyScreen({ decks, cards, stats, lang, frame = {} }, tr) {
  const sorted = arr(decks).filter(isObject).sort(byName);
  return screenFrame(
    { ...frame, title: tr("Study", lang), lang },
    tr,
    statsBlock(stats, lang, tr),
    sorted.length || isObject(stats)
      ? h("section", { class: "detail-section" }, h("h2", {}, tr("Decks", lang)), sorted.length ? h("ul", { class: "list" }, ...sorted.map((d) => deckBlock(d, arr(cards).filter(isObject), lang, tr))) : h("p", { class: "empty" }, tr("Nothing here yet", lang)))
      : h("p", { class: "empty" }, tr("Nothing here yet", lang)),
  );
}
