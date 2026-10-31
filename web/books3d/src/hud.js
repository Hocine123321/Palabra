// A conventional 2D interface layer for browsers (the iOS app draws the same controls natively in SwiftUI).
const CSS = `
.h-root{position:fixed;inset:0;pointer-events:none;font:500 15px -apple-system,BlinkMacSystemFont,"SF Pro Rounded","Segoe UI",system-ui,sans-serif;color:#1f1d1a}
.h-glass{pointer-events:auto;background:rgba(252,251,248,.72);backdrop-filter:blur(18px) saturate(1.3);-webkit-backdrop-filter:blur(18px) saturate(1.3);border:1px solid rgba(255,255,255,.55);box-shadow:0 8px 28px rgba(31,29,26,.18);border-radius:22px}
.h-dark .h-glass{background:rgba(38,37,34,.68);color:#f1efe8;border-color:rgba(255,255,255,.12)}
.h-top{position:absolute;left:12px;right:12px;top:calc(env(safe-area-inset-top,0px) + 10px);display:flex;gap:8px;align-items:center;justify-content:space-between;transition:opacity .4s}
.h-bottom{position:absolute;left:12px;right:12px;bottom:calc(env(safe-area-inset-bottom,0px) + 12px);display:flex;flex-direction:column;gap:8px;align-items:center;transition:opacity .4s}
.h-btn{pointer-events:auto;min-width:44px;height:44px;border-radius:22px;border:0;background:none;color:inherit;font:inherit;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:0 12px;cursor:pointer}
.h-btn[aria-pressed=true]{background:#d97757;color:#1f1d1a}
.h-btn:disabled{opacity:.35}
.h-row{display:flex;gap:2px;padding:4px;align-items:center}
.h-title{font-weight:700;padding:0 14px;text-align:center;flex:1;pointer-events:none}
.h-seg{display:flex;padding:3px;gap:2px}
.h-seg .h-btn{height:36px;font-size:13px;border-radius:14px;padding:0 10px}
.h-term{position:absolute;left:14px;right:14px;bottom:calc(env(safe-area-inset-bottom,0px) + 92px);padding:12px 14px;pointer-events:auto}
.h-term b{display:block;color:#a9502f;margin-bottom:4px;font-size:17px}
.h-dark .h-term b{color:#e89574}
.h-hidden{opacity:0;pointer-events:none!important}
.h-hidden *{pointer-events:none!important}
.h-shelf{position:absolute;left:12px;right:12px;bottom:calc(env(safe-area-inset-bottom,0px) + 14px);display:flex;gap:8px;justify-content:center}
.h-count{min-width:70px;text-align:center;font-weight:700;font-variant-numeric:tabular-nums}
svg{width:20px;height:20px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
`;
const I = {
  back: '<svg viewBox="0 0 24 24"><path d="M15 6l-6 6 6 6"/></svg>', fwd: '<svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>',
  lens: '<svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L21 21"/></svg>',
  mark: '<svg viewBox="0 0 24 24"><path d="M6 3h12v18l-6-4-6 4z"/></svg>',
  ruler: '<svg viewBox="0 0 24 24"><rect x="3" y="8" width="18" height="8" rx="2"/><path d="M7 8v3M11 8v4M15 8v3M19 8v4"/></svg>',
  focus: '<svg viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>',
  eye: '<svg viewBox="0 0 24 24"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
  text: '<svg viewBox="0 0 24 24"><path d="M4 18l5-13 5 13M6 13h6M16 18l3-8 3 8"/></svg>',
  close: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
};

export function mountHud(app) {
  const style = document.createElement('style'); style.textContent = CSS; document.head.appendChild(style);
  const root = document.createElement('div'); root.className = 'h-root'; document.body.appendChild(root);
  const btn = (id, html, label, fn) => `<button class="h-btn" data-id="${id}" aria-label="${label}">${html}</button>`;
  root.innerHTML = `
    <div class="h-top h-glass-wrap" data-top>
      <div class="h-glass h-row"><button class="h-btn" data-id="back" aria-label="Back to the desk">${I.back}</button></div>
      <div class="h-title" data-title></div>
      <div class="h-glass h-row">
        <button class="h-btn" data-id="size" aria-label="Text size">${I.text}</button>
        <button class="h-btn" data-id="focus" aria-label="Focus Mode" aria-pressed="false">${I.focus}</button>
      </div>
    </div>
    <div class="h-shelf" data-shelf></div>
    <div class="h-term h-glass h-hidden" data-term></div>
    <div class="h-bottom" data-bottom>
      <div class="h-glass h-seg" data-levels>
        <button class="h-btn" data-level="1" aria-pressed="true">Essential</button><button class="h-btn" data-level="2" aria-pressed="false">Key facts</button><button class="h-btn" data-level="3" aria-pressed="false">Intensive</button>
        <button class="h-btn" data-id="reveal" aria-label="Reveal page">${I.eye}</button>
      </div>
      <div class="h-glass h-row">
        <button class="h-btn" data-id="prev" aria-label="Previous page">${I.back}</button>
        <span class="h-count" data-count></span>
        <button class="h-btn" data-id="next" aria-label="Next page">${I.fwd}</button>
        <span style="width:8px"></span>
        <button class="h-btn" data-id="lens" aria-label="Magnifying glass" aria-pressed="false">${I.lens}</button>
        <button class="h-btn" data-id="bookmark" aria-label="Bookmark" aria-pressed="false">${I.mark}</button>
        <button class="h-btn" data-id="ruler" aria-label="Reading ruler" aria-pressed="false">${I.ruler}</button>
        <button class="h-btn" data-id="recall" aria-label="Memorize" aria-pressed="false" style="font-weight:700">Memorize</button>
      </div>
    </div>`;
  const q = (s) => root.querySelector(s);
  const top = q('[data-top]'), bottom = q('[data-bottom]'), shelf = q('[data-shelf]'), term = q('[data-term]'), levels = q('[data-levels]');
  const sizes = [-1, 0, 1, 2];
  root.addEventListener('click', (e) => {
    const t = e.target.closest('button'); if (!t) return;
    const id = t.dataset.id;
    if (t.dataset.level) return app.command({ name: 'setLevel', level: Number(t.dataset.level) });
    if (t.dataset.book) return app.command({ name: 'openBook', bookId: t.dataset.book });
    const s = app.snapshot();
    switch (id) {
      case 'back': app.command({ name: 'closeBook' }); break;
      case 'prev': app.command({ name: s.rtl ? 'prev' : 'prev' }); break;
      case 'next': app.command({ name: 'next' }); break;
      case 'lens': case 'bookmark': case 'ruler': app.command({ name: 'setTool', tool: id }); break;
      case 'recall': app.command({ name: 'setRecall', enabled: !s.recall }); break;
      case 'focus': app.command({ name: 'setFocus', on: !s.focus }); break;
      case 'reveal': app.command({ name: 'togglePageReveal' }); break;
      case 'size': app.command({ name: 'setTextSize', size: sizes[(sizes.indexOf(s.textSize) + 1) % sizes.length] }); break;
      default: break;
    }
  });
  const base = app.post;
  app.onState = (s) => {
    root.classList.toggle('h-dark', !!s.dark);
    const reading = s.mode === 'reading' || s.mode === 'opening';
    top.classList.toggle('h-hidden', !reading || s.focus && false);
    bottom.classList.toggle('h-hidden', s.mode !== 'reading');
    shelf.classList.toggle('h-hidden', s.mode !== 'menu');
    if (s.mode === 'menu') {
      shelf.innerHTML = (s.books || []).map((b) => `<button class="h-glass h-btn" data-book="${b.id}" style="padding:0 18px">${b.subject === 'history' ? 'History' : 'Geography'} · ${b.pages ? b.pages + ' pages' : 'empty'}</button>`).join('');
    }
    q('[data-title]').textContent = s.title || '';
    q('[data-count]').textContent = `${s.page} / ${s.pageCount}`;
    for (const id of ['lens', 'bookmark', 'ruler']) q(`[data-id=${id}]`).setAttribute('aria-pressed', String(s.tool === id));
    q('[data-id=focus]').setAttribute('aria-pressed', String(!!s.focus));
    q('[data-id=recall]').setAttribute('aria-pressed', String(!!s.recall));
    q('[data-id=prev]').disabled = !s.canPrev; q('[data-id=next]').disabled = !s.canNext;
    levels.classList.toggle('h-hidden', !s.recall);
    levels.style.display = s.recall ? 'flex' : 'none';
    levels.querySelectorAll('[data-level]').forEach((b) => b.setAttribute('aria-pressed', String(Number(b.dataset.level) === s.level)));
    if (s.term) { term.innerHTML = `<b>${s.term.term}</b>${s.term.definition}`; term.classList.remove('h-hidden'); term.dir = s.rtl ? 'rtl' : 'ltr'; }
    else term.classList.add('h-hidden');
    // let the 3D camera keep clear of the controls
    const tb = top.getBoundingClientRect(), bb = bottom.getBoundingClientRect();
    const t = reading && !s.focus ? Math.round(tb.bottom) : 0; const b = s.mode === 'reading' && !s.focus ? Math.round(window.innerHeight - bb.top) : (s.mode === 'menu' ? 70 : 0);
    if (!app._insetLock && (app.insets.top !== t || app.insets.bottom !== b)) { app._insetLock = true; app.setInsets(t, b); app._insetLock = false; }
  };
  app.onState(app.snapshot());
  return root;
}
