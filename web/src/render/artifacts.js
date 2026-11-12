// Artifact pages. A spec page is shown from the blocks the phone resolved; an app is only listed (its page never leaves the phone).
import { h, screenFrame } from "../view.js";
import { blockNodes } from "./blocks.js";
import { arr, isObject, parseTime, str } from "./util.js";

const newest = (a, b) => (parseTime(b.updatedAt) ?? 0) - (parseTime(a.updatedAt) ?? 0);
const isApp = (a) => a.kind === "app";

export function artifactList({ artifacts, lang, frame = {} }, tr) {
  const all = arr(artifacts).filter(isObject).sort(newest);
  const ordered = [...all.filter((a) => !isApp(a)), ...all.filter(isApp)];
  const rows = ordered.map((a) =>
    h(
      "li",
      { class: "row" },
      isApp(a) || !str(a.id) ? h("span", { class: "headword", dir: "auto" }, str(a.title)) : h("a", { class: "headword", dir: "auto", href: `#/artifacts/${a.id}` }, str(a.title)),
      isApp(a) ? h("span", { class: "secondary" }, tr("Open this on your phone", lang)) : null,
    ),
  );
  return screenFrame({ ...frame, title: tr("Artifacts", lang), lang }, tr, rows.length ? h("ul", { class: "list" }, ...rows) : h("p", { class: "empty" }, tr("Nothing here yet", lang)));
}

export function artifactScreen({ artifact, lang, frame = {} }, tr) {
  const back = h("a", { class: "back", href: "#/artifacts" }, tr("Back to artifacts", lang));
  if (!isObject(artifact)) return screenFrame({ ...frame, title: tr("Artifacts", lang), lang }, tr, back, h("p", { class: "empty" }, tr("That item is gone", lang)));
  let body;
  if (isApp(artifact)) body = h("p", { class: "empty" }, tr("Open this on your phone", lang));
  else if (!Array.isArray(artifact.blocks)) body = h("p", { class: "empty" }, tr("This page can't be shown here", lang));
  else body = h("div", { class: "artifact-page" }, ...blockNodes(artifact.blocks, tr, lang));
  return screenFrame({ ...frame, title: str(artifact.title), titleDir: "auto", lang }, tr, back, body);
}
