// Draws lesson pages onto canvases that the 3D leaves use as textures.
// Layout (line breaking, blocks, pagination) is pure and testable; drawing needs a 2D canvas.
import { parseInline } from './markup.js';

export const PAGE_W = 1280;
export const PAGE_H = 1820;
export const MARGIN = { top: 110, bottom: 130, outer: 104, gutter: 152 };
export const CONTENT_W = PAGE_W - MARGIN.outer - MARGIN.gutter;
export const FONT = 'Amiri, "Geeza Pro", "Noto Naskh Arabic", Georgia, serif';

export const PALETTES = {
  history: {
    paper: '#f3e8cd', paperShade: '#e6d5ae', ink: '#2b1d12', inkDim: '#6a5a46', accent: '#7a1f2b',
    rule: '#b79f73', card: 'rgba(122,31,43,0.07)', cardEdge: 'rgba(122,31,43,0.35)', blot: '#34261a',
    mark: ['', 'rgba(242,184,75,0.62)', 'rgba(242,184,75,0.40)', 'rgba(242,184,75,0.22)'],
  },
  geography: {
    paper: '#eef0e4', paperShade: '#d9e0d0', ink: '#16272a', inkDim: '#4e6360', accent: '#1f6f78',
    rule: '#a9bdb4', card: 'rgba(31,111,120,0.08)', cardEdge: 'rgba(31,111,120,0.38)', blot: '#1e3a3f',
    mark: ['', 'rgba(242,184,75,0.62)', 'rgba(242,184,75,0.40)', 'rgba(242,184,75,0.22)'],
  },
};
export function paletteFor(subject) { return PALETTES[subject] || PALETTES.history; }

/** A measuring function backed by a 2D context (cached), or any `(text, font) => width`. */
export function makeMeasure(ctx) {
  const cache = new Map();
  return (text, font) => {
    const key = font + '|' + text;
    let w = cache.get(key);
    if (w === undefined) { ctx.font = font; w = ctx.measureText(text).width; cache.set(key, w); }
    return w;
  };
}

// ---------------------------------------------------------------------------------------------
// Rich text -> wrapped lines
// ---------------------------------------------------------------------------------------------

function fontOf(size, weight) { return `${weight} ${Math.round(size)}px ${FONT}`; }

/** Splits inline markup into words made of styled fragments (a word can hold several fragments: "[[1815|e]]،"). */
function toWords(source) {
  const words = [];
  let cur = null;
  const push = (frag) => { if (!cur) { cur = { frags: [] }; words.push(cur); } cur.frags.push(frag); };
  for (const seg of parseInline(source)) {
    const pieces = seg.text.split(/(\s+)/);
    for (const piece of pieces) {
      if (piece === '') continue;
      if (/^\s+$/.test(piece)) { cur = null; continue; }
      const frag = { text: piece, kind: seg.type };
      if (seg.type === 'term') frag.id = seg.id;
      if (seg.type === 'recall') { frag.level = seg.level; frag.index = seg.index; frag.target = seg.text; }
      push(frag);
    }
  }
  return words;
}

/**
 * Wraps `source` into lines. Coordinates are local to the content column: x in [0, width].
 * @returns {{height:number, lines:Array, runs:Array, terms:Array}}
 */
export function layoutRich(source, o) {
  const { measure, width, rtl, size, weight = 400, lineHeight = 1.85, slot } = o;
  const words = toWords(source);
  const spaceW = measure(' ', fontOf(size, 400)) || size * 0.25;
  const lh = size * lineHeight;
  const lines = [];
  let line = null;
  let used = 0;
  const newLine = () => { line = { words: [] }; lines.push(line); used = 0; };
  for (const word of words) {
    let w = 0;
    for (const f of word.frags) {
      f.font = fontOf(size, f.kind === 'bold' ? 700 : weight);
      f.w = measure(f.text, f.font);
      w += f.w;
    }
    word.w = w;
    if (!line) newLine();
    const need = line.words.length ? used + spaceW + w : w;
    if (need > width && line.words.length) { newLine(); }
    used = line.words.length ? used + spaceW + w : w;
    line.words.push(word);
  }
  if (!lines.length) newLine();

  const runs = [];
  const terms = [];
  const out = [];
  lines.forEach((ln, li) => {
    const top = li * lh;
    const placed = [];
    let cursor = rtl ? width : 0;
    ln.words.forEach((word, wi) => {
      if (wi > 0) cursor += rtl ? -spaceW : spaceW;
      let wx = rtl ? cursor - word.w : cursor;
      const fragsOut = [];
      const order = rtl ? [...word.frags] : word.frags;
      let fx = rtl ? wx + word.w : wx;
      for (const f of order) {
        const x = rtl ? fx - f.w : fx;
        fragsOut.push({ ...f, x });
        fx += rtl ? -f.w : f.w;
      }
      cursor += rtl ? -word.w : word.w;
      placed.push(...fragsOut);
    });
    // Merge neighbouring fragments of one recall target (and the gap between its words) into runs.
    let open = null;
    const flush = () => { if (open) { runs.push(open); open = null; } };
    for (const f of placed) {
      if (f.kind === 'recall') {
        const key = `${slot}.${f.index}`;
        f.runKey = key;
        if (open && open.key === key) {
          const x0 = Math.min(open.x, f.x); const x1 = Math.max(open.x + open.w, f.x + f.w);
          open.x = x0; open.w = x1 - x0;
        } else {
          flush();
          open = { key, level: f.level, x: f.x, w: f.w, top, h: lh, text: f.target };
        }
      } else { flush(); }
      if (f.kind === 'term') terms.push({ id: f.id, x: f.x, w: f.w, top, h: lh });
    }
    flush();
    out.push({ top, frags: placed, baseline: top + size * 1.18 + (lh - size * 1.6) * 0.5 });
  });
  return { height: lines.length * lh, lines: out, runs, terms, size, lh };
}

// ---------------------------------------------------------------------------------------------
// Blocks -> display lists
// ---------------------------------------------------------------------------------------------

/** A block layout: `height`, plus `draw(ctx, x, y, st)` and `hits(x, y)` closures over local coordinates. */
function textBlock(rich, color, extra = {}) {
  return {
    height: rich.height,
    rich, color,
    kind: 'text',
    ...extra,
  };
}

export function layoutBlock(block, index, env) {
  const { measure, rtl, scale: s, palette: P, width: W } = env;
  const slot = (name) => `${index}.${name}`;
  const rich = (src, name, o = {}) => layoutRich(src, { measure, rtl, width: W, slot: slot(name), ...o });
  const parts = []; // {x, y, w?, h?, ...}
  let y = 0;
  const add = (part) => parts.push(part);
  const text = (r, x, yy, color, extra = {}) => add({ t: 'rich', r, x, y: yy, color, ...extra });
  const startX = (x, w) => (rtl ? W - x - w : x); // place a box of width w at inset x from the start edge

  switch (block.type) {
    case 'heading': {
      const size = (block.level <= 1 ? 76 : block.level === 2 ? 60 : 50) * s;
      const r = rich(block.text, 'h', { size, weight: 700, lineHeight: 1.45 });
      text(r, 0, 0, P.ink);
      y = r.height;
      if (block.level <= 2) { add({ t: 'rect', x: startX(0, 90 * s), y: y + 6, w: 90 * s, h: 5, fill: P.accent, r: 2 }); y += 26; }
      break;
    }
    case 'paragraph': {
      const r = rich(block.text, 'p', { size: 52 * s });
      text(r, 0, 0, P.ink); y = r.height; break;
    }
    case 'list': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 8 * s; }
      const mark = 64 * s;
      (block.items || []).forEach((item, i) => {
        const r = rich(item, `i${i}`, { size: 50 * s, width: W - mark });
        add({ t: 'label', text: block.ordered ? String(i + 1) : '•', x: startX(0, mark), y, w: mark, size: 44 * s, color: P.accent, bold: true, align: rtl ? 'right' : 'left', lh: r.lh });
        text(r, rtl ? 0 : mark, y, P.ink); y += r.height + 12 * s;
      });
      y -= 12 * s; break;
    }
    case 'keyPoint': {
      const pad = 30 * s; const bar = 10 * s;
      const inner = W - pad * 2 - bar;
      let yy = pad;
      let r1 = null;
      if (block.label) { r1 = rich(block.label, 'l', { size: 34 * s, weight: 700, width: inner, lineHeight: 1.5 }); }
      const r2 = rich(block.text, 'k', { size: 54 * s, weight: 700, width: inner, lineHeight: 1.7 });
      const h = pad * 2 + (r1 ? r1.height + 6 * s : 0) + r2.height;
      add({ t: 'rect', x: 0, y: 0, w: W, h, fill: P.card, stroke: P.cardEdge, r: 22 });
      add({ t: 'rect', x: startX(0, bar), y: 0, w: bar, h, fill: P.accent, r: 4 });
      const tx = rtl ? pad : pad + bar;
      if (r1) { text(r1, tx, yy, P.accent); yy += r1.height + 6 * s; }
      text(r2, tx, yy, P.ink); y = h; break;
    }
    case 'quote': {
      const bar = 8 * s; const pad = 34 * s;
      const inner = W - bar - pad;
      const r = rich(block.text, 'q', { size: 54 * s, width: inner });
      let h = r.height; let src = null;
      if (block.source) { src = rich(block.source, 's', { size: 38 * s, width: inner }); h += src.height + 10 * s; }
      add({ t: 'rect', x: startX(0, bar), y: 0, w: bar, h, fill: P.rule, r: 4 });
      const tx = rtl ? 0 : bar + pad;
      text(r, tx, 0, P.ink); if (src) text(src, tx, r.height + 10 * s, P.inkDim);
      y = h; break;
    }
    case 'timeline': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 12 * s; }
      const gutter = 70 * s; const inner = W - gutter;
      const evs = block.events || [];
      evs.forEach((ev, i) => {
        const d = rich(ev.date, `e${i}d`, { size: 42 * s, weight: 700, width: inner, lineHeight: 1.5 });
        const t = rich(ev.title, `e${i}t`, { size: 50 * s, weight: 700, width: inner, lineHeight: 1.6 });
        const x = ev.detail ? rich(ev.detail, `e${i}x`, { size: 44 * s, width: inner, lineHeight: 1.7 }) : null;
        const h = d.height + t.height + (x ? x.height : 0) + 26 * s;
        const tx = rtl ? 0 : gutter;
        add({ t: 'dot', cx: rtl ? W - 18 * s : 18 * s, cy: 22 * s + y, r: 11 * s, fill: P.accent });
        if (i < evs.length - 1) add({ t: 'rect', x: rtl ? W - 18 * s - 2 : 18 * s - 2, y: y + 38 * s, w: 4, h: h - 22 * s, fill: P.rule, r: 2 });
        text(d, tx, y, P.accent); text(t, tx, y + d.height, P.ink); if (x) text(x, tx, y + d.height + t.height, P.inkDim);
        y += h;
      });
      y -= 20 * s; break;
    }
    case 'stats': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 12 * s; }
      const gap = 26 * s; const cw = (W - gap) / 2;
      const items = block.items || [];
      let rowH = 0;
      items.forEach((it, i) => {
        const col = i % 2; const px = rtl ? W - cw - col * (cw + gap) : col * (cw + gap);
        const pad = 22 * s; const inner = cw - pad * 2;
        const v = rich(it.value, `v${i}`, { size: 78 * s, weight: 700, width: inner, lineHeight: 1.3 });
        const l = rich(it.label, `l${i}`, { size: 40 * s, width: inner, lineHeight: 1.6 });
        const n = it.note ? rich(it.note, `n${i}`, { size: 34 * s, width: inner, lineHeight: 1.6 }) : null;
        const h = pad * 2 + v.height + l.height + (n ? n.height : 0);
        add({ t: 'rect', x: px, y, w: cw, h, fill: P.card, stroke: P.cardEdge, r: 20 });
        text(v, px + pad, y + pad, P.accent);
        text(l, px + pad, y + pad + v.height, P.ink);
        if (n) text(n, px + pad, y + pad + v.height + l.height, P.inkDim);
        rowH = Math.max(rowH, h);
        if (col === 1 || i === items.length - 1) { y += rowH + gap; rowH = 0; }
      });
      y -= gap; break;
    }
    case 'comparison': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 12 * s; }
      const cols = block.columns || [];
      const rows = block.rows || [];
      if (cols.length < 2) {
        rows.forEach((row, r) => {
          const pad = 26 * s; const inner = W - pad * 2;
          const lab = rich(row.label, `r${r}l`, { size: 48 * s, weight: 700, width: inner, lineHeight: 1.55 });
          const cell = String(row.cells[0] || '').split('\n');
          const cells = cell.map((c, k) => rich(c, `r${r}c0n${k}`, { size: 46 * s, width: inner - (cell.length > 1 ? 40 * s : 0), lineHeight: 1.75 }));
          const h = pad * 2 + lab.height + cells.reduce((a, c) => a + c.height + 6 * s, 0);
          add({ t: 'rect', x: 0, y, w: W, h, fill: P.card, stroke: P.cardEdge, r: 22 });
          text(lab, pad, y + pad, P.accent);
          let yy = y + pad + lab.height + 6 * s;
          cells.forEach((c) => {
            if (cell.length > 1) add({ t: 'label', text: '•', x: rtl ? W - pad - 30 * s : pad, y: yy, w: 30 * s, size: 40 * s, color: P.accent, bold: true, align: rtl ? 'right' : 'left', lh: c.lh });
            text(c, pad + (cell.length > 1 && !rtl ? 40 * s : 0), yy, P.ink);
            yy += c.height + 6 * s;
          });
          y += h + 22 * s;
        });
        y -= 22 * s;
      } else {
        const n = cols.length; const labelW = W * 0.24; const cw = (W - labelW) / n;
        const hdr = cols.map((c, i) => rich(c, `c${i}`, { size: 38 * s, weight: 700, width: cw - 20 * s, lineHeight: 1.5 }));
        const hh = Math.max(...hdr.map((h) => h.height)) + 20 * s;
        const colX = (i) => (rtl ? W - labelW - (i + 1) * cw : labelW + i * cw);
        hdr.forEach((h, i) => text(h, colX(i) + 10 * s, y + 10 * s, P.accent));
        add({ t: 'rect', x: 0, y: y + hh, w: W, h: 3, fill: P.rule });
        y += hh + 8 * s;
        rows.forEach((row, r) => {
          const lab = rich(row.label, `r${r}l`, { size: 42 * s, weight: 700, width: labelW - 20 * s, lineHeight: 1.5 });
          const cells = row.cells.map((c, i) => rich(c, `r${r}c${i}`, { size: 40 * s, width: cw - 20 * s, lineHeight: 1.65 }));
          const h = Math.max(lab.height, ...cells.map((c) => c.height)) + 24 * s;
          text(lab, (rtl ? W - labelW + 10 * s : 10 * s), y + 12 * s, P.ink);
          cells.forEach((c, i) => text(c, colX(i) + 10 * s, y + 12 * s, P.ink));
          add({ t: 'rect', x: 0, y: y + h, w: W, h: 2, fill: P.rule });
          y += h + 4 * s;
        });
      }
      break;
    }
    case 'causeEffect': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 14 * s; }
      const stages = block.stages || [];
      stages.forEach((st, si) => {
        const last = si === stages.length - 1;
        if (st.label) { const l = rich(st.label, `s${si}l`, { size: 34 * s, weight: 700, lineHeight: 1.5 }); text(l, 0, y, P.accent); y += l.height + 4 * s; }
        (st.nodes || []).forEach((node, ni) => {
          const pad = 24 * s;
          const r = rich(node, `s${si}n${ni}`, { size: 46 * s, weight: last ? 700 : 400, width: W - pad * 2, lineHeight: 1.7 });
          const h = r.height + pad * 2;
          add({ t: 'rect', x: 0, y, w: W, h, fill: last ? 'rgba(122,31,43,0.14)' : P.card, stroke: last ? P.accent : P.cardEdge, r: 20, lw: last ? 3 : 2 });
          text(r, pad, y + pad, P.ink);
          y += h + 14 * s;
        });
        if (!last) { add({ t: 'arrow', cx: W / 2, y: y, h: 44 * s, color: P.accent }); y += 58 * s; }
      });
      y -= 14 * s; break;
    }
    case 'process': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 12 * s; }
      const gutter = 80 * s; const inner = W - gutter;
      const steps = block.steps || [];
      steps.forEach((st, i) => {
        const a = rich(st.title, `s${i}t`, { size: 50 * s, weight: 700, width: inner, lineHeight: 1.6 });
        const b = st.detail ? rich(st.detail, `s${i}d`, { size: 44 * s, width: inner, lineHeight: 1.7 }) : null;
        const h = a.height + (b ? b.height : 0) + 22 * s;
        add({ t: 'num', cx: rtl ? W - 26 * s : 26 * s, cy: y + 30 * s, r: 24 * s, n: i + 1, size: 30 * s, fill: P.accent, color: P.paper });
        if (i < steps.length - 1) add({ t: 'rect', x: rtl ? W - 26 * s - 2 : 26 * s - 2, y: y + 56 * s, w: 4, h: h - 30 * s, fill: P.rule, r: 2 });
        text(a, rtl ? 0 : gutter, y, P.ink); if (b) text(b, rtl ? 0 : gutter, y + a.height, P.inkDim);
        y += h;
      });
      y -= 22 * s; break;
    }
    case 'definitions': {
      if (block.title) { const t = rich(block.title, 't', { size: 40 * s, weight: 700 }); text(t, 0, y, P.accent); y += t.height + 12 * s; }
      (block.definitions || []).forEach((d, i) => {
        const pad = 26 * s; const inner = W - pad * 2;
        const a = rich(d.term, `d${i}t`, { size: 52 * s, weight: 700, width: inner, lineHeight: 1.6 });
        const b = rich(d.definition, `d${i}x`, { size: 46 * s, width: inner, lineHeight: 1.75 });
        const h = pad * 2 + a.height + b.height;
        add({ t: 'rect', x: 0, y, w: W, h, fill: P.card, stroke: P.cardEdge, r: 22 });
        text(a, pad, y + pad, P.accent); text(b, pad, y + pad + a.height, P.ink);
        y += h + 20 * s;
      });
      y -= 20 * s; break;
    }
    case 'image': {
      const h = 420 * s;
      add({ t: 'image', name: block.image, alt: block.alt || '', x: 0, y: 0, w: W, h });
      y = h;
      if (block.caption) { const c = rich(block.caption, 'cap', { size: 36 * s, lineHeight: 1.6 }); text(c, 0, y + 12 * s, P.inkDim); y += c.height + 12 * s; }
      break;
    }
    default: {
      const r = rich('…', 'u', { size: 40 * s });
      text(r, 0, 0, P.inkDim); y = r.height;
    }
  }
  return { height: Math.max(0, y), parts, index };
}

// ---------------------------------------------------------------------------------------------
// Pagination: a lesson page may need more than one physical page.
// ---------------------------------------------------------------------------------------------

export const GAP = 40;

/** Title lines, date position and where the header rule sits (shared by pagination and drawing). */
export function headerLayout(info, measure) {
  const first = info.part === 1;
  const size = first ? 70 : 54;
  const title = info.title + (info.parts > 1 ? ` · ${info.part}/${info.parts}` : '');
  const font = fontOf(size, 700);
  const words = title.split(/\s+/);
  const lines = []; let cur = '';
  for (const w of words) {
    const t = cur ? cur + ' ' + w : w;
    if (measure(t, font) > CONTENT_W && cur) { lines.push(cur); cur = w; } else cur = t;
  }
  if (cur) lines.push(cur);
  const titleY = MARGIN.top + (first ? 110 : 88);
  const lastBaseline = titleY + (lines.length - 1) * size * 1.3;
  const dateY = first && info.dateLabel ? lastBaseline + 52 : null;
  const ruleY = (dateY || lastBaseline) + 34;
  return { size, lines, titleY, dateY, ruleY, bodyY: ruleY + 60 };
}
export function capacityFor(info, measure) { return PAGE_H - MARGIN.bottom - headerLayout(info, measure).bodyY; }

/**
 * @param {object} bookPage  {id, page:{id,title,dateLabel,blocks}, glossary, lessonTitle}
 * @returns {Array<{id,baseId,part,parts,blocks:Array<{layout,index}>,scale}>}
 */
export function paginate(bookPage, env) {
  const blocks = bookPage.page.blocks || [];
  const palette = env.palette || paletteFor(env.subject);
  const measureAt = (scale) => blocks.map((b, i) => layoutBlock(b, i, { ...env, palette, scale, width: CONTENT_W }));
  const total = (ls) => ls.reduce((a, l) => a + l.height, 0) + Math.max(0, ls.length - 1) * GAP;
  const infoOf = (part, parts) => ({ title: bookPage.page.title, dateLabel: bookPage.page.dateLabel || null, part, parts });
  const capacity = (first) => capacityFor(infoOf(first ? 1 : 2, 2), env.measure);

  // Try the preferred scale first, then shrink a little to avoid a near-empty second page.
  let scale = env.scale;
  let layouts = measureAt(scale);
  const cap1 = capacityFor(infoOf(1, 1), env.measure);
  if (total(layouts) > cap1) {
    for (const f of [0.94, 0.88]) {
      const trial = measureAt(scale * f);
      if (total(trial) <= cap1) { layouts = trial; scale *= f; break; }
    }
  }
  const pages = [];
  let cur = [];
  let used = 0;
  const first = () => pages.length === 0;
  layouts.forEach((layout, index) => {
    const add = (cur.length ? GAP : 0) + layout.height;
    if (cur.length && used + add > capacity(first())) { pages.push(cur); cur = []; used = 0; }
    cur.push({ layout, index });
    used += (cur.length > 1 ? GAP : 0) + layout.height;
  });
  if (cur.length || !pages.length) pages.push(cur);
  return pages.map((blks, i) => ({
    id: pages.length === 1 ? bookPage.id : `${bookPage.id}~${i + 1}`,
    baseId: bookPage.id, part: i + 1, parts: pages.length, blocks: blks, scale,
    title: bookPage.page.title, dateLabel: bookPage.page.dateLabel || null,
    lessonTitle: bookPage.lessonTitle, glossary: bookPage.glossary, bookPage,
  }));
}

// ---------------------------------------------------------------------------------------------
// Recall state (mirrors Palabra/Features/Books/Domain/RecallState.swift)
// ---------------------------------------------------------------------------------------------

export class RecallState {
  constructor(level = 1) { this.enabled = false; this.level = level; this.revealedPages = new Set(); this.overrides = new Map(); }
  static conceals(level, target) { return target <= level; }
  setEnabled(on) { if (on === this.enabled) return false; this.enabled = on; this.clear(); return true; }
  setLevel(l) { if (l === this.level) return false; this.level = l; this.clear(); return true; }
  clear() { this.revealedPages.clear(); this.overrides.clear(); }
  inPlay(target) { return this.enabled && RecallState.conceals(this.level, target); }
  isRevealed(key, pageId) { return this.overrides.has(key) ? this.overrides.get(key) : this.revealedPages.has(pageId); }
  isConcealed(target, key, pageId) { return this.inPlay(target) && !this.isRevealed(key, pageId); }
  toggle(key, pageId) { this.overrides.set(key, !this.isRevealed(key, pageId)); }
  revealPage(id) { this.revealedPages.add(id); this._drop(id); }
  hidePage(id) { this.revealedPages.delete(id); this._drop(id); }
  isPageRevealed(id) { return this.revealedPages.has(id); }
  _drop(id) { const prefix = id + '#'; for (const k of [...this.overrides.keys()]) if (k.startsWith(prefix)) this.overrides.delete(k); }
  /** Key for a recall run on a page. */
  static key(pageId, runKey) { return `${pageId}#${runKey}`; }
}

// ---------------------------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------------------------

let noiseTile = null;
function paperNoise(doc) {
  if (noiseTile) return noiseTile;
  const c = doc.createElement('canvas'); c.width = c.height = 256;
  const g = c.getContext('2d');
  let seed = 7;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  for (let i = 0; i < 2600; i++) {
    g.fillStyle = rnd() > 0.5 ? 'rgba(90,60,20,0.05)' : 'rgba(255,255,255,0.10)';
    g.fillRect(rnd() * 256, rnd() * 256, 1 + rnd() * 2, 1 + rnd() * 2);
  }
  for (let i = 0; i < 60; i++) {
    g.strokeStyle = 'rgba(120,90,40,0.04)'; g.beginPath();
    const x = rnd() * 256, y = rnd() * 256; g.moveTo(x, y); g.lineTo(x + (rnd() - 0.5) * 60, y + (rnd() - 0.5) * 8); g.stroke();
  }
  noiseTile = c; return c;
}

function roundRect(g, x, y, w, h, r) {
  const rr = Math.min(r, w / 2, h / 2);
  g.beginPath(); g.moveTo(x + rr, y); g.arcTo(x + w, y, x + w, y + h, rr); g.arcTo(x + w, y + h, x, y + h, rr);
  g.arcTo(x, y + h, x, y, rr); g.arcTo(x, y, x + w, y, rr); g.closePath();
}

/**
 * Draws a physical page. Returns hit regions in canvas pixels (before `scale`):
 *   {kind:'recall'|'term', x, y, w, h, key|id, level}
 * @param {object} opts {face:'front'|'back', rtl, subject, recall:RecallState|null, revealAll:boolean, scale:number, images}
 */
export function drawPage(canvas, phys, opts) {
  const g = canvas.getContext('2d');
  const k = canvas.width / PAGE_W;
  const P = paletteFor(opts.subject);
  const rtl = !!opts.rtl;
  const gutterLeft = (opts.face === 'front') !== rtl;
  const left = gutterLeft ? MARGIN.gutter : MARGIN.outer;
  const hits = [];
  g.setTransform(k, 0, 0, k, 0, 0);
  g.fillStyle = P.paper; g.fillRect(0, 0, PAGE_W, PAGE_H);
  const pat = g.createPattern(paperNoise(canvas.ownerDocument || document), 'repeat');
  g.fillStyle = pat; g.fillRect(0, 0, PAGE_W, PAGE_H);
  // Foxing: a soft darker rim, stronger at the outer edge and toward the gutter.
  const grad = g.createLinearGradient(gutterLeft ? 0 : PAGE_W, 0, gutterLeft ? PAGE_W : 0, 0);
  grad.addColorStop(0, 'rgba(70,45,15,0.20)'); grad.addColorStop(0.12, 'rgba(70,45,15,0.04)'); grad.addColorStop(1, 'rgba(70,45,15,0)');
  g.fillStyle = grad; g.fillRect(0, 0, PAGE_W, PAGE_H);
  const rim = g.createLinearGradient(0, 0, 0, PAGE_H);
  rim.addColorStop(0, 'rgba(70,45,15,0.10)'); rim.addColorStop(0.05, 'rgba(70,45,15,0)'); rim.addColorStop(0.95, 'rgba(70,45,15,0)'); rim.addColorStop(1, 'rgba(70,45,15,0.12)');
  g.fillStyle = rim; g.fillRect(0, 0, PAGE_W, PAGE_H);

  if (!phys) return hits; // blank sheet

  const st = opts.recall;
  const dim = !!(st && st.enabled && !opts.revealAll);
  g.textBaseline = 'alphabetic';

  const drawRich = (r, ox, oy, color) => {
    for (const ln of r.lines) {
      const base = oy + ln.baseline;
      for (const run of r.runs) {
        if (run.top !== ln.top) continue;
        const absKey = RecallState.key(phys.id, run.key);
        const concealed = !opts.revealAll && st && st.isConcealed(run.level, absKey, phys.id);
        const x = ox + run.x, y = oy + run.top + r.lh * 0.12, w = run.w, h = r.lh * 0.78;
        if (concealed) {
          // Ink blot: the answer is not drawn at all.
          roundRect(g, x - 6, y, w + 12, h, 14);
          const bg = g.createLinearGradient(0, y, 0, y + h);
          bg.addColorStop(0, P.blot); bg.addColorStop(1, '#1b130b');
          g.fillStyle = bg; g.fill();
          g.strokeStyle = 'rgba(242,184,75,0.55)'; g.lineWidth = 3; g.stroke();
          hits.push({ kind: 'recall', x: x - 10, y: y - 6, w: w + 20, h: h + 12, key: absKey, level: run.level });
        } else {
          const inPlay = st && st.inPlay(run.level);
          const mk = opts.revealAll && st && st.enabled ? 'rgba(242,184,75,0.55)' : P.mark[run.level];
          roundRect(g, x - 5, y + 4, w + 10, h - 4, 10);
          g.fillStyle = mk; g.fill();
          if (inPlay) hits.push({ kind: 'recall', x: x - 10, y: y - 6, w: w + 20, h: h + 12, key: absKey, level: run.level });
        }
      }
      for (const f of ln.frags) {
        // Concealed recall fragments are skipped (the blot is already drawn); everything else is drawn.
        if (f.kind === 'recall' && !opts.revealAll && st && st.isConcealed(f.level, RecallState.key(phys.id, f.runKey), phys.id)) continue;
        g.font = f.font;
        g.direction = rtl ? 'rtl' : 'ltr';
        g.textAlign = rtl ? 'right' : 'left';
        let col = color;
        if (dim && f.kind !== 'recall') col = P.inkDim;
        if (f.kind === 'term') col = P.accent;
        g.fillStyle = col;
        const tx = ox + (rtl ? f.x + f.w : f.x);
        g.fillText(f.text, tx, base);
        if (f.kind === 'term') {
          g.strokeStyle = P.accent; g.lineWidth = 3; g.setLineDash([2, 7]); g.lineCap = 'round';
          g.beginPath(); g.moveTo(ox + f.x, base + 12); g.lineTo(ox + f.x + f.w, base + 12); g.stroke(); g.setLineDash([]);
        }
      }
      for (const t of r.terms) {
        if (t.top !== ln.top) continue;
        hits.push({ kind: 'term', x: ox + t.x - 8, y: oy + t.top, w: t.w + 16, h: r.lh, id: t.id });
      }
    }
  };

  const drawPart = (p, ox, oy) => {
    switch (p.t) {
      case 'rect': {
        roundRect(g, ox + p.x, oy + p.y, p.w, p.h, p.r || 0);
        if (p.fill) { g.fillStyle = p.fill; g.fill(); }
        if (p.stroke) { g.strokeStyle = p.stroke; g.lineWidth = p.lw || 2; g.stroke(); }
        break;
      }
      case 'dot': g.fillStyle = p.fill; g.beginPath(); g.arc(ox + p.cx, oy + p.cy, p.r, 0, Math.PI * 2); g.fill(); break;
      case 'num': {
        g.fillStyle = p.fill; g.beginPath(); g.arc(ox + p.cx, oy + p.cy, p.r, 0, Math.PI * 2); g.fill();
        g.fillStyle = p.color; g.font = fontOf(p.size, 700); g.textAlign = 'center'; g.direction = 'ltr';
        g.fillText(String(p.n), ox + p.cx, oy + p.cy + p.size * 0.36); break;
      }
      case 'arrow': {
        g.strokeStyle = p.color; g.fillStyle = p.color; g.lineWidth = 6; g.lineCap = 'round'; g.lineJoin = 'round';
        g.beginPath(); g.moveTo(ox + p.cx, oy + p.y); g.lineTo(ox + p.cx, oy + p.y + p.h - 14); g.stroke();
        g.beginPath(); g.moveTo(ox + p.cx - 16, oy + p.y + p.h - 26); g.lineTo(ox + p.cx, oy + p.y + p.h); g.lineTo(ox + p.cx + 16, oy + p.y + p.h - 26); g.closePath(); g.fill(); break;
      }
      case 'label': {
        g.font = fontOf(p.size, p.bold ? 700 : 400); g.fillStyle = p.color; g.direction = 'ltr';
        g.textAlign = p.align === 'right' ? 'right' : 'left';
        g.fillText(p.text, ox + (p.align === 'right' ? p.x + p.w : p.x), oy + p.y + (p.lh || p.size * 1.6) * 0.72); break;
      }
      case 'image': {
        roundRect(g, ox + p.x, oy + p.y, p.w, p.h, 18);
        g.fillStyle = P.card; g.fill(); g.strokeStyle = P.cardEdge; g.lineWidth = 3; g.setLineDash([14, 10]); g.stroke(); g.setLineDash([]);
        const img = opts.images && opts.images[p.name];
        if (img) { g.save(); roundRect(g, ox + p.x, oy + p.y, p.w, p.h, 18); g.clip(); g.drawImage(img, ox + p.x, oy + p.y, p.w, p.h); g.restore(); }
        else { g.fillStyle = P.inkDim; g.font = fontOf(34, 400); g.textAlign = 'center'; g.direction = rtl ? 'rtl' : 'ltr'; g.fillText(p.alt, ox + p.x + p.w / 2, oy + p.y + p.h / 2); }
        break;
      }
      default: break;
    }
  };

  // Header
  const H = headerLayout(phys, opts.measure);
  const align = rtl ? 'right' : 'left';
  const hx = rtl ? left + CONTENT_W : left;
  g.direction = rtl ? 'rtl' : 'ltr'; g.textAlign = align;
  g.font = fontOf(30, 700); g.fillStyle = P.accent;
  g.fillText(phys.lessonTitle, hx, MARGIN.top + 26);
  g.font = fontOf(H.size, 700); g.fillStyle = P.ink;
  H.lines.forEach((ln, i) => g.fillText(ln, hx, H.titleY + i * H.size * 1.3));
  if (H.dateY) { g.font = fontOf(30, 400); g.fillStyle = P.inkDim; g.fillText(phys.dateLabel, hx, H.dateY); }
  const ry = H.ruleY;
  const ax = rtl ? left + CONTENT_W - 120 : left;
  g.fillStyle = P.rule; g.fillRect(left, ry + 2, CONTENT_W, 2);
  g.fillStyle = P.accent; g.fillRect(ax, ry, 120, 5);

  // Blocks
  let by = H.bodyY;
  for (const b of phys.blocks) {
    for (const p of b.layout.parts) {
      if (p.t === 'rich') {
        drawRich(p.r, left + p.x, by + p.y, p.color);
      } else {
        drawPart(p, left, by);
      }
    }
    by += b.layout.height + GAP;
  }

  // Folio (page number)
  g.font = fontOf(34, 400); g.fillStyle = P.inkDim; g.textAlign = 'center'; g.direction = 'ltr';
  g.fillText(`— ${phys.number} —`, PAGE_W / 2, PAGE_H - 62);
  return hits;
}
