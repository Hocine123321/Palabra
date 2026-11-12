// One word with everything the phone sent: the lesson content in its sections, and any section the page does not know as
// plain text. `content` may be missing or any type; nothing here throws.
import { h, screenFrame } from "../view.js";
import { arr, isObject, str } from "./util.js";

const KNOWN = new Set(["word", "examples", "meaning", "usage", "forms", "similarWords", "contentLanguage"]);

const section = (title, ...children) => h("section", { class: "detail-section" }, h("h2", {}, title), ...children);
const para = (text, extra = {}) => h("p", { dir: "auto", ...extra }, text);

/** Any value as lines of text (objects as "key: value"), never as markup. */
function plainLines(value, depth = 0) {
  if (depth > 4) return [];
  if (Array.isArray(value)) return value.flatMap((v) => plainLines(v, depth + 1));
  if (isObject(value)) return Object.entries(value).flatMap(([k, v]) => plainLines(v, depth + 1).map((line) => `${k}: ${line}`));
  const text = str(value) || (typeof value === "boolean" ? String(value) : "");
  return text ? [text] : [];
}

function contentSections(content, tr, lang) {
  if (!isObject(content)) {
    const lines = plainLines(content);
    return lines.length ? [section(tr("Details", lang), ...lines.map((l) => para(l)))] : [];
  }
  const out = [];
  const examples = arr(content.examples).filter(isObject);
  if (examples.length) {
    out.push(
      section(
        tr("Examples", lang),
        ...examples.map((e) => h("div", { class: "example" }, str(e.context) ? h("p", { class: "secondary", dir: "auto" }, e.context) : null, para(str(e.spanish), { class: "spanish" }), para(str(e.translation ?? e.english), { class: "translation" }))),
      ),
    );
  }
  const meaning = content.meaning;
  if (isObject(meaning) && (arr(meaning.translations).length || str(meaning.explanation))) {
    out.push(section(tr("Meaning", lang), arr(meaning.translations).length ? para(arr(meaning.translations).map(str).filter(Boolean).join(", "), { class: "translations" }) : null, str(meaning.explanation) ? para(meaning.explanation) : null));
  }
  const usage = content.usage;
  if (isObject(usage) && (str(usage.explanation) || str(usage.register) || str(usage.nuance))) {
    out.push(section(tr("Usage and register", lang), str(usage.explanation) ? para(usage.explanation) : null, str(usage.register) ? para(`${tr("Register", lang)}: ${usage.register}`, { class: "secondary" }) : null, str(usage.nuance) ? para(usage.nuance) : null));
  }
  const forms = content.forms;
  if (isObject(forms) && (arr(forms.groups).length || str(forms.partOfSpeech))) {
    out.push(
      section(
        tr("Forms", lang),
        str(forms.partOfSpeech) ? para(forms.partOfSpeech, { class: "secondary" }) : null,
        ...arr(forms.groups).filter(isObject).map((g) => h("div", { class: "form-group" }, h("h3", { dir: "auto" }, str(g.label)), h("ul", {}, ...arr(g.items).filter(isObject).map((i) => h("li", { dir: "auto" }, str(i.form), str(i.note) ? h("span", { class: "secondary" }, ` (${i.note})`) : null))))),
      ),
    );
  }
  const similar = arr(content.similarWords).filter(isObject);
  if (similar.length) {
    out.push(section(tr("Similar words", lang), h("ul", {}, ...similar.map((s) => h("li", { dir: "auto" }, h("strong", {}, str(s.word)), ` ${str(s.difference)}`)))));
  }
  for (const [key, value] of Object.entries(content)) {
    if (KNOWN.has(key)) continue;
    const lines = plainLines(value);
    if (lines.length) out.push(section(key, ...lines.map((l) => para(l))));
  }
  return out;
}

/** `frame` carries what every screen shows (navigation, refresh, freshness); `word` is the opened row's data or null. */
export function wordDetail({ word, lang, frame = {} }, tr) {
  if (!isObject(word)) {
    return screenFrame({ ...frame, title: tr("Your words", lang), lang }, tr, h("p", { class: "empty" }, tr("That item is gone", lang)), h("a", { class: "back", href: "#/words" }, tr("Back to words", lang)));
  }
  return screenFrame(
    { ...frame, title: str(word.spanish), titleDir: "auto", lang },
    tr,
    h("a", { class: "back", href: "#/words" }, tr("Back to words", lang)),
    str(word.translation) ? h("p", { class: "translation big", dir: "auto" }, word.translation) : null,
    h("p", { class: "meta" }, ...[str(word.partOfSpeech), str(word.category)].filter(Boolean).map((t) => h("span", { class: "category", dir: "auto" }, t)), ...arr(word.tags).map((tag) => h("span", { class: "tag", dir: "auto" }, str(tag)))),
    ...contentSections(word.content, tr, lang),
  );
}
