// Turns the payload the app sends (raw catalogue + lesson JSON) into books and numbered pages.
// Mirrors Palabra/Features/Books/Domain/BookLibrary.swift (page ids are "lesson/page").
import { plainText } from './markup.js';

export function isRightToLeft(language) {
  return /^(ar|he|fa|ur|ps|sd|ug|yi|dv)(-|_|$)/i.test(String(language || ''));
}

function glossaryOf(lesson) {
  const out = {};
  for (const [id, def] of Object.entries(lesson.terms || {})) {
    out[id] = { term: plainText(def.term), definition: plainText(def.definition) };
  }
  for (const page of lesson.pages || []) {
    for (const block of page.blocks || []) {
      if (block.type !== 'definitions') continue;
      for (const item of block.definitions || []) {
        if (!item.id || out[item.id]) continue;
        out[item.id] = { term: plainText(item.term), definition: plainText(item.definition) };
      }
    }
  }
  return out;
}

/**
 * @param {{catalogue:{books:Array}, lessons:Object<string,object>}} payload
 * @returns {{books: Array, problems: string[]}}
 */
export function buildLibrary(payload) {
  const problems = [];
  const books = [];
  const catalogue = payload && payload.catalogue;
  if (!catalogue || !Array.isArray(catalogue.books)) return { books, problems: ['catalogue missing'] };
  const seenBooks = new Set();
  for (const entry of catalogue.books) {
    if (seenBooks.has(entry.id)) { problems.push('duplicate book id ' + entry.id); continue; }
    seenBooks.add(entry.id);
    let number = 0;
    const chapters = [];
    const pages = [];
    const seenLessons = new Set();
    for (const chapter of entry.chapters || []) {
      const lessons = [];
      for (const ref of chapter.lessons || []) {
        const label = `${entry.id}/${ref.id}`;
        if (!ref.id || ref.id.includes('/') || seenLessons.has(ref.id)) { problems.push(label + ': bad or duplicate lesson id'); continue; }
        seenLessons.add(ref.id);
        const lesson = payload.lessons && payload.lessons[ref.file];
        if (!lesson) { problems.push(label + ': lesson file missing'); continue; }
        const glossary = glossaryOf(lesson);
        const lessonPages = [];
        const seenPages = new Set();
        for (const page of lesson.pages || []) {
          if (seenPages.has(page.id)) continue;
          seenPages.add(page.id);
          number += 1;
          const bp = {
            id: `${ref.id}/${page.id}`, number, chapterId: chapter.id, lessonId: ref.id,
            lessonTitle: lesson.title, page, glossary,
          };
          lessonPages.push(bp);
          pages.push(bp);
        }
        lessons.push({
          id: ref.id, chapterId: chapter.id, title: lesson.title, summary: lesson.summary || null,
          notes: lesson.transcriptionNotes || [], pages: lessonPages,
        });
      }
      chapters.push({ id: chapter.id, title: chapter.title, lessons });
    }
    books.push({
      id: entry.id, subject: entry.subject, title: entry.title, language: entry.language || 'en',
      rtl: isRightToLeft(entry.language), chapters, pages,
    });
  }
  return { books, problems };
}

/** Saved page id -> index in book.pages; falls back to the start of its lesson, then 0. */
export function resumeIndex(book, lastPageId) {
  if (!lastPageId) return 0;
  const exact = book.pages.findIndex((p) => p.id === lastPageId);
  if (exact >= 0) return exact;
  const slash = lastPageId.indexOf('/');
  if (slash > 0) {
    const lessonId = lastPageId.slice(0, slash);
    const start = book.pages.findIndex((p) => p.lessonId === lessonId);
    if (start >= 0) return start;
  }
  return 0;
}
