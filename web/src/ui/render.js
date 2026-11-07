// HTML for the read-only screens, as strings. Every piece of text that came from the phone goes through `esc`,
// so a word like <img onerror=...> is shown as text and never runs.
import { libraryView, studyView, activityView, syncedParts } from "./model.js";
import { makeT } from "./strings.js";

export const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const initial = (text) => esc([...String(text ?? "?")][0]?.toUpperCase() ?? "?");

export function renderLibrary(snapshot, filters = {}, t = makeT("en")) {
  const v = libraryView(snapshot, filters);
  if (v.isEmpty) return `<section class="empty"><h2>${t("No words yet")}</h2><p>${t("Words you add in Palabra on the phone appear here.")}</p></section>`;
  const chips = [
    `<button class="chip${filters.tag ? "" : " on"}" data-tag="">${t("All")}</button>`,
    ...v.tags.map((t) => `<button class="chip${filters.tag === t ? " on" : ""}" data-tag="${esc(t)}">${esc(t)}</button>`),
  ].join("");
  const body = v.noMatches
    ? `<section class="empty"><h2>${t("No matches")}</h2><p>${t("Try a different word or clear the filters.")}</p></section>`
    : v.groups.map((g) => `
      <section class="group">
        <h2>${g.name === null ? t("No section") : esc(g.name)} <span class="count">${g.words.length}</span></h2>
        <ul class="words">${g.words.map((w) => `
          <li class="word" data-id="${esc(w.id)}">
            <span class="tile" style="background:var(--tint-${w.tint})">${initial(w.spanish)}</span>
            <span class="text"><span class="es" lang="es">${esc(w.spanish)}</span><span class="tr">${esc(w.translation)}</span></span>
            <span class="pos">${esc(w.partOfSpeech)}</span>
          </li>`).join("")}
        </ul>
      </section>`).join("");
  return `
    <div class="toolbar">
      <input id="search" type="search" placeholder="${t("Search words")}" value="${esc(filters.query ?? "")}" aria-label="${t("Search words")}">
      <span class="count">${v.shown} ${t("of")} ${v.total}</span>
    </div>
    <div class="chips" role="group" aria-label="${t("Filter by tag")}">${chips}</div>
    ${body}`;
}

export function renderStudy(snapshot, t = makeT("en")) {
  const v = studyView(snapshot);
  const a = activityView(snapshot);
  const decks = v.hasDecks
    ? `<ul class="decks">${v.decks.map((d) => `
        <li class="deck"><span class="name">${esc(d.name)}</span>
          <span class="nums"><b>${d.due}</b> ${t("due")} <b>${d.new}</b> ${t("new")} <span class="muted">${t("of")} ${d.total}</span></span></li>`).join("")}</ul>`
    : `<section class="empty"><h2>${t("No decks yet")}</h2><p>${t("Decks you make in Palabra appear here.")}</p></section>`;
  const review = v.hasReview
    ? `<ul class="review">${v.review.map((r) => `
        <li><span class="es" lang="es">${esc(r.headword)}</span><span class="tr">${esc(r.translation)}</span>
          <span class="bar" title="${Math.round((r.score ?? 0) * 100)}%"><i style="width:${Math.round((r.score ?? 0) * 100)}%"></i></span></li>`).join("")}</ul>`
    : `<p class="muted">${t("Nothing is flagged for review.")}</p>`;
  const chart = a.days.length
    ? `<div class="chart" role="img" aria-label="${t("Words added per day")}">${a.days.map((d) =>
        `<span class="col" title="${esc(d.day)}: ${d.count}"><i style="height:${d.height}%"></i></span>`).join("")}</div>
       <p class="muted">${t("{total} added in the last {days} days").replace("{total}", a.total).replace("{days}", a.days.length)}</p>`
    : "";
  return `
    <div class="summary"><div><b>${v.dueTotal}</b><span>${t("due today")}</span></div><div><b>${v.newTotal}</b><span>${t("new")}</span></div></div>
    <h2>${t("Decks")}</h2>${decks}
    <h2>${t("Needs review")}</h2>${review}
    ${chart ? `<h2>${t("Activity")}</h2>${chart}` : ""}`;
}

export function renderStatus({ state, takenAt, now = new Date(), message = "" }, t = makeT("en")) {
  const label = { linked: t("Linked to your phone"), connecting: t("Connecting…"), away: t("Phone away, showing saved data"), empty: t("Phone not reachable"), error: message }[state] ?? "";
  const p = syncedParts(takenAt, now);
  const synced = p.kind === "never" ? t("Not synced yet") : p.kind === "now" ? t("Synced just now") : t(`Synced {n} ${p.unit} ago`).replace("{n}", p.n);
  return `<span class="dot ${esc(state)}"></span><span>${esc(label)}</span><span class="muted">${esc(synced)}</span>`;
}

/** The box for adding words. It works offline: the words wait in the queue until the phone is back. */
export function renderAddWords(t = makeT("en")) {
  return `<form id="add" class="add glass" autocomplete="off">
    <input id="addText" type="text" maxlength="400" placeholder="${esc(t("Add words, separated by commas"))}" aria-label="${esc(t("Add words, separated by commas"))}">
    <button type="submit" class="chip">${t("Add")}</button></form>`;
}

/** What each queued capability means to a person, without jargon. */
export function describeChange(item, t = makeT("en")) {
  const n = (item.args?.words ?? []).length;
  if (item.capability === "words.add") return t("Add {n} words").replace("{n}", n);
  if (item.capability === "words.place") return t("Organise {n} words").replace("{n}", n);
  if (item.capability === "review.flag") return t("Flag {n} words for review").replace("{n}", n);
  return t("A change");
}

/** Waiting changes and the ones the phone refused. Empty string when there is nothing to show. */
export function renderChanges({ queue = [], review = [] }, t = makeT("en"), reasonLabel = (r) => r) {
  if (!queue.length && !review.length) return "";
  const waiting = queue.length
    ? `<h2>${t("Waiting for the phone")}</h2><ul class="changes">${queue.map((q) => `
        <li><span>${esc(describeChange(q, t))}</span><button class="chip" data-cancel="${esc(q.id)}">${t("Cancel")}</button></li>`).join("")}</ul>`
    : "";
  const needs = review.length
    ? `<h2>${t("Needs your review")}</h2><ul class="changes review-list">${review.map((r) => `
        <li><span>${esc(describeChange(r, t))}<small class="muted">${esc(reasonLabel(r.reason))}</small></span>
          <span class="actions"><button class="chip" data-retry="${esc(r.id)}">${t("Try again")}</button><button class="chip" data-drop="${esc(r.id)}">${t("Drop")}</button></span></li>`).join("")}</ul>`
    : "";
  return waiting + needs;
}
