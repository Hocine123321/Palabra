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
  const label = { linked: t("Linked to your phone"), connecting: t("Connecting…"), away: t("Phone away, showing saved data"), error: message }[state] ?? "";
  const p = syncedParts(takenAt, now);
  const synced = p.kind === "never" ? t("Not synced yet") : p.kind === "now" ? t("Synced just now") : t(`Synced {n} ${p.unit} ago`).replace("{n}", p.n);
  return `<span class="dot ${esc(state)}"></span><span>${esc(label)}</span><span class="muted">${esc(synced)}</span>`;
}
