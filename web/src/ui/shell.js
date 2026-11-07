// The page: pairing card, link, snapshot, tabs. Thin on purpose; the logic it calls is tested in Node.
import { pairWithPhone, openLink } from "../link-client.js";
import { renderLibrary, renderStudy, renderStatus } from "./render.js";
import { makeT, pickLanguage, dirFor, errorText } from "./strings.js";

const $ = (s) => document.querySelector(s);

export function start(root = document) {
  const state = { snapshot: null, takenAt: null, tab: "library", filters: {}, link: "idle", message: "" };
  const isFile = location.protocol === "file:";
  const lang = pickLanguage(navigator.languages?.length ? navigator.languages : [navigator.language]);
  const t = makeT(lang);
  document.documentElement.lang = lang;
  document.documentElement.dir = dirFor(lang);
  for (const node of document.querySelectorAll("[data-i18n]")) node.textContent = t(node.dataset.i18n);
  for (const node of document.querySelectorAll("[data-i18n-aria]")) node.setAttribute("aria-label", t(node.dataset.i18nAria));

  function paint() {
    if (!state.snapshot) return;
    $("#status").innerHTML = renderStatus({ state: state.link, takenAt: state.takenAt, message: state.message }, t);
    $("#view").innerHTML = state.tab === "library" ? renderLibrary(state.snapshot, state.filters, t) : renderStudy(state.snapshot, t);
    for (const b of document.querySelectorAll("nav.tabs button")) b.toggleAttribute("aria-current", b.dataset.tab === state.tab) || b.removeAttribute("aria-current");
    for (const b of document.querySelectorAll("nav.tabs button[aria-current]")) b.setAttribute("aria-current", "page");
    const search = $("#search");
    if (search) search.addEventListener("input", (e) => { state.filters.query = e.target.value; const at = e.target.selectionStart; paint(); const s = $("#search"); s.focus(); s.setSelectionRange(at, at); });
    for (const c of document.querySelectorAll(".chip")) c.addEventListener("click", () => { state.filters.tag = c.dataset.tag || null; paint(); });
  }

  for (const b of document.querySelectorAll("nav.tabs button")) b.addEventListener("click", () => { state.tab = b.dataset.tab; paint(); });

  $("#pair").addEventListener("submit", async (event) => {
    event.preventDefault();
    const go = $("#go"); go.disabled = true; $("#err").textContent = "";
    try {
      const secret = await pairWithPhone({ address: $("#address").value, code: $("#code").value.trim(), isFileOrigin: isFile });
      state.link = "connecting"; $("#pairing").hidden = true; $("#app").hidden = false;
      const link = await openLink({ relayUrl: $("#relay").value.trim(), secret });
      const reply = await link.request("snapshot");
      state.snapshot = reply.snapshot; state.takenAt = reply.takenAt; state.link = "linked";
      paint();
    } catch (e) {
      $("#pairing").hidden = false; $("#app").hidden = true;
      $("#err").textContent = errorText(e, t);
    } finally { go.disabled = false; }
  });
}
