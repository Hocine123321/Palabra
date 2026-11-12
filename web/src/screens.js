// The signed-in page: the opened items grouped by kind, and which screen a route shows.
import { navBar } from "./nav.js";
import { artifactList, artifactScreen } from "./render/artifacts.js";
import { bookReader, booksScreen } from "./render/books.js";
import { chatScreen } from "./render/chat.js";
import { reviewScreen } from "./render/review.js";
import { studyScreen } from "./render/study.js";
import { wordDetail } from "./render/word.js";
import { arr } from "./render/util.js";
import { h, screenFrame, wordsScreen } from "./view.js";

const time = (v) => (typeof v === "string" && Number.isFinite(Date.parse(v)) ? Date.parse(v) : 0);

/** Rows from the local copy -> lists by kind. Each entry is the phone's data plus `id` (the item id, used in links) and `recordId`. */
export function buildModel(rows) {
  const by = {};
  for (const row of arr(rows)) {
    if (!row || typeof row.kind !== "string" || row.d === null || typeof row.d !== "object") continue;
    (by[row.kind] ??= []).push({ ...row.d, id: row.id, recordId: row.recordId });
  }
  const list = (kind) => by[kind] ?? [];
  return {
    words: list("word").sort((a, b) => time(b.createdAt) - time(a.createdAt)),
    decks: list("deck"),
    cards: list("card"),
    stats: list("stats")[0] ?? null,
    needs: list("review"),
    artifacts: list("artifact"),
    chat: list("chat")[0] ?? null,
    lessons: list("lesson"),
    pages: list("lessonPage"),
  };
}

export const sectionCounts = (model) => ({ words: model.words.length, review: model.needs.length, artifacts: model.artifacts.length });

/** `frame`: {syncedAt, status, freshness, onRefresh, now}. */
export function routedScreen({ route, model, frame, lang }, tr) {
  const nav = navBar({ route, lang, counts: sectionCounts(model) }, tr);
  const shared = { ...frame, nav, lang };
  switch (route.name) {
    case "word":
      return wordDetail({ word: model.words.find((w) => w.id === route.id) ?? null, lang, frame: { ...frame, nav } }, tr);
    case "words":
      return wordsScreen({ ...shared, words: model.words }, tr);
    case "study":
      return studyScreen({ decks: model.decks, cards: model.cards, stats: model.stats, lang, frame: shared }, tr);
    case "review":
      return reviewScreen({ needs: model.needs, words: model.words, lang, frame: shared }, tr);
    case "artifacts":
      return artifactList({ artifacts: model.artifacts, lang, frame: shared }, tr);
    case "artifact":
      return artifactScreen({ artifact: model.artifacts.find((a) => a.id === route.id) ?? null, lang, frame: shared }, tr);
    case "chat":
      return chatScreen({ chat: model.chat, lang, frame: shared }, tr);
    case "books":
      return booksScreen({ lessons: model.lessons, lang, frame: shared }, tr);
    case "book":
      return bookReader({ lesson: model.lessons.find((l) => l.id === route.id) ?? null, pages: model.pages, lang, frame: shared }, tr);
    default:
      return screenFrame({ ...shared, title: tr("Palabra Mirroring", lang) }, tr, h("p", { class: "empty" }, tr("Nothing here yet", lang)));
  }
}
