import { buildLibrary } from '../src/data.js';
import { paginate, drawPage, makeMeasure, RecallState, PAGE_W, PAGE_H } from '../src/pagetex.js';
window.run = async (payload, opts) => {
  await document.fonts.load('700 40px Amiri', 'ابت'); await document.fonts.load('400 40px Amiri', 'ابت');
  await document.fonts.load('700 40px Amiri', 'A1'); await document.fonts.load('400 40px Amiri', 'A1');
  const lib = buildLibrary(payload);
  const book = lib.books[0];
  const mc = document.createElement('canvas').getContext('2d');
  const measure = makeMeasure(mc);
  const rc = new RecallState(opts.level || 1); rc.setEnabled(!!opts.recall);
  let n = 0; const out = [];
  for (const bp of book.pages) {
    const phys = paginate(bp, { measure, rtl: book.rtl, scale: 1, subject: book.subject });
    for (const p of phys) { n += 1; p.number = n; out.push(p); }
  }
  document.body.style.cssText = 'margin:0;display:flex;flex-wrap:wrap;gap:8px;background:#444;overflow:auto';
  out.forEach((p, i) => {
    const c = document.createElement('canvas'); c.width = 640; c.height = 910; c.style.cssText = 'width:640px;height:910px';
    document.body.appendChild(c);
    drawPage(c, p, { measure, face: i % 2 === 0 ? 'front' : 'back', rtl: book.rtl, subject: book.subject, recall: rc, revealAll: !!opts.reveal });
  });
  return out.map((p) => `${p.id} blocks=${p.blocks.length}`);
};
