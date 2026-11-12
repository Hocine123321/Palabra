// Books lessons: the list by book and chapter, and a reader that follows the lesson's own language direction.
import { h, screenFrame } from "../view.js";
import { blockNodes } from "./blocks.js";
import { arr, inline, isObject, str } from "./util.js";

const RTL = new Set(["ar", "he", "fa", "ur", "ps", "sd", "ug", "yi"]);
/** The reading direction of a lesson from its language, whatever the browser's language is. */
export const dirOfLanguage = (language) => (RTL.has(str(language).toLowerCase().split("-")[0]) ? "rtl" : "ltr");
const text = (a, b) => str(a).localeCompare(str(b));

export function booksScreen({ lessons, lang, frame = {} }, tr) {
  const all = arr(lessons).filter(isObject).sort((a, b) => text(a.bookTitle, b.bookTitle) || text(a.chapterTitle, b.chapterTitle) || text(a.title, b.title));
  const books = [];
  for (const lesson of all) {
    let book = books.find((b) => b.id === lesson.bookId);
    if (!book) books.push((book = { id: lesson.bookId, title: str(lesson.bookTitle), chapters: [] }));
    let chapter = book.chapters.find((c) => c.id === lesson.chapterId);
    if (!chapter) book.chapters.push((chapter = { id: lesson.chapterId, title: str(lesson.chapterTitle), lessons: [] }));
    chapter.lessons.push(lesson);
  }
  return screenFrame(
    { ...frame, title: tr("Books", lang), lang },
    tr,
    books.length
      ? h(
          "div",
          {},
          ...books.map((book) =>
            h(
              "section",
              { class: "detail-section" },
              h("h2", { dir: "auto" }, book.title),
              ...book.chapters.map((chapter) =>
                h("div", { class: "chapter" }, h("h3", { dir: "auto" }, chapter.title), h("ul", { class: "list" }, ...chapter.lessons.map((l) => h("li", { class: "row" }, str(l.id) ? h("a", { class: "headword", dir: "auto", href: `#/books/${l.id}` }, str(l.title)) : h("span", { class: "headword", dir: "auto" }, str(l.title)), str(l.summary) ? h("span", { class: "secondary", dir: "auto" }, l.summary) : null)))),
              ),
            ),
          ),
        )
      : h("p", { class: "empty" }, tr("Nothing here yet", lang)),
  );
}

export function bookReader({ lesson, pages, lang, frame = {} }, tr) {
  const back = h("a", { class: "back", href: "#/books" }, tr("Back to books", lang));
  if (!isObject(lesson)) return screenFrame({ ...frame, title: tr("Books", lang), lang }, tr, back, h("p", { class: "empty" }, tr("That item is gone", lang)));
  const mine = arr(pages).filter((p) => isObject(p) && p.lessonId === lesson.recordId).sort((a, b) => (Number.isFinite(a.number) ? a.number : 0) - (Number.isFinite(b.number) ? b.number : 0));
  const expected = arr(lesson.pageIds).length;
  const terms = isObject(lesson.terms) ? Object.values(lesson.terms).filter(isObject) : [];
  const notes = arr(lesson.notes).map(str).filter(Boolean);
  const language = str(lesson.language) || "en";
  return screenFrame(
    { ...frame, title: inline(lesson.title), titleDir: "auto", lang },
    tr,
    back,
    h(
      "div",
      { class: "reader", dir: dirOfLanguage(language), lang: language },
      str(lesson.summary) ? h("p", { class: "secondary", dir: "auto" }, lesson.summary) : null,
      expected > mine.length ? h("p", { class: "status", role: "status" }, tr("Some pages have not arrived yet", lang)) : null,
      mine.length
        ? h("section", { class: "detail-section" }, h("h2", {}, tr("Pages", lang)), h("ol", { class: "toc" }, ...mine.map((p) => h("li", { dir: "auto" }, inline(p.title)))))
        : h("p", { class: "empty" }, tr("Nothing here yet", lang)),
      ...mine.map((p) =>
        h("article", { class: "lesson-page" }, h("h2", { dir: "auto" }, inline(p.title)), str(p.dateLabel) ? h("p", { class: "secondary", dir: "auto" }, p.dateLabel) : null, ...blockNodes(p.blocks, tr, language)),
      ),
      terms.length ? h("section", { class: "detail-section" }, h("h2", {}, tr("Terms", lang)), h("dl", { class: "definitions" }, ...terms.flatMap((d) => [h("dt", { dir: "auto" }, str(d.term)), h("dd", { dir: "auto" }, str(d.definition))]))) : null,
      notes.length ? h("section", { class: "detail-section" }, h("h2", {}, tr("Notes", lang)), h("ul", {}, ...notes.map((n) => h("li", { dir: "auto" }, n)))) : null,
    ),
  );
}
