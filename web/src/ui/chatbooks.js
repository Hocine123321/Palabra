// Chat and Books on the page. The phone sends plain text; this file only draws it.
// Nothing from the phone is ever treated as HTML: every string goes through esc(), unknown block kinds draw nothing, and the
// counts are capped again here (a page must not trust the phone's limits blindly).
import { makeT } from "./strings.js";
import { esc } from "./render.js";

export const CHAT_MAX_TURNS = 80;
export const LESSON_MAX_PAGES = 80;
export const LESSON_MAX_BLOCKS = 100;
export const CHAT_MAX_TEXT = 6000;
const list_of = (v) => (Array.isArray(v) ? v : []);
const clip = (v) => String(v ?? "").slice(0, CHAT_MAX_TEXT);

/** The latest conversation, read-only. Sending messages from the page is not offered: it needs the phone's AI settings. */
export function renderChat(result, t = makeT("en")) {
  const chat = result?.chat;
  if (!chat || typeof chat !== "object") return `<section class="empty"><h2>${t("No chats yet")}</h2><p>${t("Your latest chat from the phone appears here.")}</p></section>`;
  const turns = list_of(chat.turns).slice(-CHAT_MAX_TURNS);
  return `<h2>${esc(clip(chat.title))}</h2><p class="muted small">${t("Latest chat. To reply, open it on your phone.")}</p><div class="chat">${turns.map((turn) => {
    const mine = turn?.role === "user";
    const did = Number(turn?.actions) > 0 ? `<small class="muted">${esc(t("Ran {n} actions on the phone").replace("{n}", Math.min(Math.round(Number(turn.actions)), 99)))}</small>` : "";
    const failed = turn?.failed ? `<small class="err">${esc(t("This message did not go through."))}</small>` : "";
    return `<div class="bubble ${mine ? "me" : "them"}"><p>${esc(clip(turn?.text))}</p>${did}${failed}</div>`;
  }).join("")}</div>`;
}

/** The books list: each lesson opens a text version of its pages. */
export function renderBooks(list, t = makeT("en")) {
  const books = list_of(list);
  if (!books.length) return `<section class="empty"><h2>${t("No books yet")}</h2><p>${t("Lessons are added to the app in updates.")}</p></section>`;
  return books.slice(0, 50).map((book) => `<section class="book"><h2>${esc(clip(book?.title))}</h2>${list_of(book?.chapters).slice(0, 100).map((chapter) =>
    `<h3>${esc(clip(chapter?.title))}</h3><ul class="artifacts">${list_of(chapter?.lessons).slice(0, 100).map((lesson) =>
      `<li><button class="open" data-book="${esc(book?.id)}" data-lesson="${esc(lesson?.id)}"><span class="name">${esc(clip(lesson?.title))}</span></button></li>`).join("")}</ul>`).join("")}</section>`).join("");
}

/** One lesson as text. Visual parts the phone could not reduce to text arrive as notes. */
export function renderLesson(lesson, t = makeT("en")) {
  if (!lesson || !Array.isArray(lesson.pages)) return `<p class="muted">${t("This page could not be shown.")}</p>`;
  let left = LESSON_MAX_BLOCKS;
  const pages = list_of(lesson.pages).slice(0, LESSON_MAX_PAGES).map((page) => `<article class="lesson-page"><h3>${esc(clip(page?.title))}</h3>${list_of(page?.blocks).map((b) => {
    if (left <= 0) return "";
    left -= 1;
    return lessonPiece(b, t);
  }).join("")}</article>`).join("");
  return `<button class="chip" id="lessonBack">${t("Back")}</button><h2>${esc(clip(lesson.title))}</h2>${pages}`;
}

function lessonPiece(b, t) {
  const items = list_of(b?.items).slice(0, 100).map(clip);
  switch (b?.kind) {
    case "heading": { const level = Math.min(Math.max(Math.round(Number(b.level)) || 1, 1), 3) + 3; return `<h${level}>${esc(clip(b.text))}</h${level}>`; }
    case "text": return `<p>${esc(clip(b.text))}</p>`;
    case "list": { const tag = b.ordered ? "ol" : "ul"; return `${b.text ? `<p><b>${esc(clip(b.text))}</b></p>` : ""}<${tag}>${items.map((i) => `<li>${esc(i)}</li>`).join("")}</${tag}>`; }
    case "keyPoint": return `<p class="key">${items[0] ? `<b>${esc(items[0])}</b> ` : ""}${esc(clip(b.text))}</p>`;
    case "quote": return `<blockquote>${esc(clip(b.text))}${items[0] ? `<footer class="muted">${esc(items[0])}</footer>` : ""}</blockquote>`;
    case "definitions": return `${b.text ? `<p><b>${esc(clip(b.text))}</b></p>` : ""}<dl>${items.map((i) => { const at = i.indexOf(": "); return at < 0 ? `<dd>${esc(i)}</dd>` : `<dt>${esc(i.slice(0, at))}</dt><dd>${esc(i.slice(at + 2))}</dd>`; }).join("")}</dl>`;
    case "note": return `<p class="muted">${esc(t("This part is best read on the phone."))}</p>`;
    default: return "";
  }
}
