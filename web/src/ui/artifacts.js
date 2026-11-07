// Artifacts on the page. The phone sends a plain block tree with tables and charts already resolved; this file only draws it.
// Nothing from an artifact is ever treated as HTML: every string goes through esc(), unknown block types draw nothing, and the
// depth and block count are capped again here (a page must not trust the phone's limits blindly).
import { makeT } from "./strings.js";
import { esc } from "./render.js";

export const MAX_DEPTH = 4;
export const MAX_BLOCKS = 60;
const arr = (v) => (Array.isArray(v) ? v : []);

/** The Artifacts tab list: pages you can open here, and apps that only run on the phone. */
export function renderArtifactList(items, t = makeT("en")) {
  const list = arr(items);
  if (!list.length) return `<section class="empty"><h2>${t("No artifacts yet")}</h2><p>${t("Pages and apps you make in Palabra appear here.")}</p></section>`;
  return `<ul class="artifacts">${list.map((a) => a.viewable
    ? `<li><button class="open" data-artifact="${esc(a.id)}"><span class="name">${esc(a.title)}</span></button></li>`
    : `<li class="phone-only"><span class="name">${esc(a.title)}</span><span class="muted">${t("Opens on your phone")}</span></li>`).join("")}</ul>`;
}

/** One artifact page. */
export function renderArtifactPage(page, t = makeT("en")) {
  if (!page || !Array.isArray(page.blocks)) return `<p class="muted">${t("This page could not be shown.")}</p>`;
  return `<button class="chip" id="artifactBack">${t("Back")}</button><h2>${esc(page.title)}</h2>${blocks(page.blocks, 0, { n: 0 }, t)}`;
}

function blocks(list, depth, budget, t) {
  if (depth >= MAX_DEPTH) return "";
  let out = "";
  for (const b of arr(list)) {
    if (budget.n >= MAX_BLOCKS) break;
    budget.n += 1;
    out += block(b, depth, budget, t);
  }
  return out;
}

function block(b, depth, budget, t) {
  switch (b?.type) {
    case "heading": { const level = Math.min(Math.max(Math.round(Number(b.level)) || 1, 1), 3) + 2; return `<h${level}>${esc(b.text)}</h${level}>`; }
    case "text": return `<p>${esc(b.text)}</p>`;
    case "note": return `<p class="muted">${esc(b.text)}</p>`;
    case "list": { const tag = b.ordered ? "ol" : "ul"; return `<${tag}>${arr(b.items).map((i) => `<li>${esc(i)}</li>`).join("")}</${tag}>`; }
    case "table": return `<div class="scroll"><table><thead><tr>${arr(b.columns).map((c) => `<th>${esc(c)}</th>`).join("")}</tr></thead><tbody>${
      arr(b.rows).map((r) => `<tr>${arr(r).map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
    case "stats": return `<div class="summary">${arr(b.tiles).map((s) => `<div><b>${esc(s.value)}</b><span>${esc(s.label)}</span></div>`).join("")}</div>`;
    case "checklist": return `<ul class="check">${arr(b.items).map((i) => `<li class="${i?.done ? "done" : ""}"><span aria-hidden="true">${i?.done ? "☑" : "☐"}</span> ${esc(i?.text)}</li>`).join("")}</ul>`;
    case "roadmap": return `<ol class="roadmap">${arr(b.steps).map((s) => `<li class="${s?.done ? "done" : ""}"><b>${esc(s?.title)}</b>${s?.detail ? `<small class="muted">${esc(s.detail)}</small>` : ""}</li>`).join("")}</ol>`;
    case "chart": return chart(b, t);
    case "columns": return `<div class="cols">${blocks(b.children, depth + 1, budget, t)}</div>`;
    case "section": return `<section><h3>${esc(b.title)}</h3>${blocks(b.children, depth + 1, budget, t)}</section>`;
    default: return "";   // an unknown block draws nothing rather than guessing
  }
}

function chart(b, t) {
  const labels = arr(b.labels), first = arr(arr(b.series)[0]?.values).map(Number).filter(Number.isFinite);
  if (!first.length) return `<p class="muted">${t("No data to chart.")}</p>`;
  const max = Math.max(...first.map((v) => Math.abs(v)), 1);
  const title = b.title ? `<p class="muted">${esc(b.title)}</p>` : "";
  return `${title}<div class="chart" role="img" aria-label="${esc(b.title ?? t("Chart"))}">${first.map((v, i) =>
    `<span class="col" title="${esc(labels[i] ?? "")}: ${esc(v)}"><i style="height:${Math.round((Math.abs(v) / max) * 100)}%"></i></span>`).join("")}</div>`;
}
