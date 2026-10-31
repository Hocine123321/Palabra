// Procedural cover materials: colour, roughness/metalness (gold foil) and grain bump maps, drawn on canvases.
import * as THREE from 'three';
import { FONT } from './pagetex.js';

const W = 1024, H = 1450;

function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function rng(seed) { let s = seed; return () => { s = (s * 16807) % 2147483647; return s / 2147483647; }; }

function grain(g, w, h, seed, dots, alphaA, alphaB) {
  const r = rng(seed);
  for (let i = 0; i < dots; i++) {
    g.fillStyle = r() > 0.5 ? `rgba(0,0,0,${alphaA})` : `rgba(255,255,255,${alphaB})`;
    const s = 1 + r() * 3; g.fillRect(r() * w, r() * h, s, s);
  }
}

function tex(c, { srgb = true, aniso = 8 } = {}) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = aniso; t.needsUpdate = true;
  return t;
}

function frame(g, x, y, w, h, r, lw) { g.lineWidth = lw; g.beginPath(); g.roundRect(x, y, w, h, r); g.stroke(); }

/** Gold foil drawn into both the colour map and the metal mask. */
function foil(color, mr, draw) {
  const gold = (() => { const g = color.createLinearGradient(0, 0, W, H); g.addColorStop(0, '#f6d27a'); g.addColorStop(0.5, '#c8962e'); g.addColorStop(1, '#f1c765'); return g; })();
  color.save(); color.fillStyle = gold; color.strokeStyle = gold; draw(color); color.restore();
  mr.save(); mr.fillStyle = 'rgb(0,60,255)'; mr.strokeStyle = 'rgb(0,60,255)'; draw(mr); mr.restore();
}

function historyCover() {
  const color = canvas(W, H), mr = canvas(W, H), bump = canvas(W, H);
  const g = color.getContext('2d'), m = mr.getContext('2d'), b = bump.getContext('2d');
  const base = g.createLinearGradient(0, 0, W, H); base.addColorStop(0, '#8f2a37'); base.addColorStop(0.55, '#6b1a25'); base.addColorStop(1, '#4a111a');
  g.fillStyle = base; g.fillRect(0, 0, W, H);
  grain(g, W, H, 11, 26000, 0.10, 0.05);
  m.fillStyle = 'rgb(0,170,0)'; m.fillRect(0, 0, W, H);
  b.fillStyle = '#808080'; b.fillRect(0, 0, W, H); grain(b, W, H, 5, 40000, 0.35, 0.35);
  foil(g, m, (c) => {
    c.lineJoin = 'round';
    frame(c, 78, 78, W - 156, H - 156, 20, 9); frame(c, 100, 100, W - 200, H - 200, 12, 3);
    // corner ornaments
    for (const [cx, cy, sx, sy] of [[130, 130, 1, 1], [W - 130, 130, -1, 1], [130, H - 130, 1, -1], [W - 130, H - 130, -1, -1]]) {
      c.save(); c.translate(cx, cy); c.scale(sx, sy); c.lineWidth = 5; c.beginPath(); c.moveTo(0, 90); c.quadraticCurveTo(0, 0, 90, 0); c.stroke();
      c.beginPath(); c.arc(34, 34, 12, 0, Math.PI * 2); c.fill(); c.restore();
    }
    // medallion
    c.lineWidth = 6; c.beginPath(); c.arc(W / 2, 480, 190, 0, Math.PI * 2); c.stroke(); c.lineWidth = 2; c.beginPath(); c.arc(W / 2, 480, 168, 0, Math.PI * 2); c.stroke();
    c.save(); c.translate(W / 2, 480); c.lineWidth = 5;
    // a columned portico
    c.beginPath(); c.moveTo(-110, -70); c.lineTo(0, -130); c.lineTo(110, -70); c.closePath(); c.stroke();
    c.fillRect(-120, -64, 240, 14);
    for (let i = -3; i <= 3; i++) c.fillRect(i * 34 - 8, -42, 16, 100);
    c.fillRect(-124, 62, 248, 14); c.fillRect(-140, 80, 280, 10);
    c.restore();
    c.font = `700 190px ${FONT}`; c.textAlign = 'center'; c.direction = 'rtl';
    c.fillText('التاريخ', W / 2, 920);
    c.font = `700 52px ${FONT}`; c.direction = 'ltr';
    c.save(); c.translate(W / 2, 1130); c.fillText('H I S T O R Y', 0, 0); c.restore();
    c.lineWidth = 3; c.beginPath(); c.moveTo(W / 2 - 220, 1185); c.lineTo(W / 2 + 220, 1185); c.stroke();
    c.beginPath(); c.arc(W / 2, 1185, 9, 0, Math.PI * 2); c.fill();
  });
  return { color: tex(color), mr: tex(mr, { srgb: false }), bump: tex(bump, { srgb: false }), edge: '#4a111a', cloth: '#5a1621' };
}

function geographyCover() {
  const color = canvas(W, H), mr = canvas(W, H), bump = canvas(W, H);
  const g = color.getContext('2d'), m = mr.getContext('2d'), b = bump.getContext('2d');
  const base = g.createLinearGradient(0, 0, W, H); base.addColorStop(0, '#2a8a96'); base.addColorStop(0.6, '#15616c'); base.addColorStop(1, '#0c4049');
  g.fillStyle = base; g.fillRect(0, 0, W, H);
  // buckram weave
  g.strokeStyle = 'rgba(255,255,255,0.045)'; g.lineWidth = 1;
  for (let x = 0; x < W; x += 4) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke(); }
  g.strokeStyle = 'rgba(0,0,0,0.07)';
  for (let y = 0; y < H; y += 4) { g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke(); }
  grain(g, W, H, 23, 14000, 0.07, 0.05);
  m.fillStyle = 'rgb(0,215,0)'; m.fillRect(0, 0, W, H);
  b.fillStyle = '#808080'; b.fillRect(0, 0, W, H);
  b.strokeStyle = 'rgba(0,0,0,0.5)'; for (let x = 0; x < W; x += 4) { b.beginPath(); b.moveTo(x, 0); b.lineTo(x, H); b.stroke(); }
  b.strokeStyle = 'rgba(255,255,255,0.5)'; for (let y = 0; y < H; y += 4) { b.beginPath(); b.moveTo(0, y); b.lineTo(W, y); b.stroke(); }
  // printed cream cartography
  const ink = 'rgba(244,238,214,0.9)';
  g.save(); g.translate(W / 2, 600);
  g.strokeStyle = ink; g.lineWidth = 3;
  for (let r = 120; r <= 380; r += 65) { g.globalAlpha = 0.9 - r / 600; g.beginPath(); g.arc(0, 0, r, 0, Math.PI * 2); g.stroke(); }
  g.globalAlpha = 0.55;
  for (let a = 0; a < 12; a++) { g.save(); g.rotate((a * Math.PI) / 12); g.beginPath(); g.ellipse(0, 0, 380 * Math.abs(Math.cos(a * Math.PI / 12 + 0.01)) + 6, 380, 0, 0, Math.PI * 2); g.stroke(); g.restore(); }
  g.globalAlpha = 1; g.lineWidth = 7; g.beginPath(); g.moveTo(-380, 0); g.lineTo(380, 0); g.stroke();
  // compass rose
  g.fillStyle = ink; for (let i = 0; i < 4; i++) { g.save(); g.rotate((i * Math.PI) / 2); g.beginPath(); g.moveTo(0, -150); g.lineTo(16, -16); g.lineTo(-16, -16); g.closePath(); g.fill(); g.restore(); }
  g.restore();
  g.fillStyle = 'rgba(244,238,214,0.95)'; g.strokeStyle = g.fillStyle; g.lineWidth = 5;
  frame(g, 72, 72, W - 144, H - 144, 8, 5);
  foil(g, m, (c) => {
    c.font = `700 200px ${FONT}`; c.textAlign = 'center'; c.direction = 'rtl';
    c.fillText('الجغرافيا', W / 2, 1150);
    c.font = `700 54px ${FONT}`; c.direction = 'ltr'; c.fillText('A T L A S', W / 2, 1250);
    c.lineWidth = 4; c.beginPath(); c.moveTo(W / 2 - 160, 1290); c.lineTo(W / 2 + 160, 1290); c.stroke();
  });
  return { color: tex(color), mr: tex(mr, { srgb: false }), bump: tex(bump, { srgb: false }), edge: '#0c3a42', cloth: '#12525d' };
}

/** Plain material for the endpaper, back cover, and cloth edges. */
function endpaper(subject) {
  const c = canvas(512, 512), g = c.getContext('2d');
  g.fillStyle = subject === 'geography' ? '#e7e9d8' : '#e9dcc0'; g.fillRect(0, 0, 512, 512);
  g.strokeStyle = subject === 'geography' ? 'rgba(31,111,120,0.22)' : 'rgba(122,31,43,0.22)'; g.lineWidth = 2;
  for (let y = -512; y < 1024; y += 28) for (let x = -512; x < 1024; x += 28) { g.beginPath(); g.arc(x + (y / 28 % 2) * 14, y, 7, 0, Math.PI * 2); g.stroke(); }
  grain(g, 512, 512, 3, 3000, 0.06, 0.1);
  const t = tex(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(2, 3);
  return t;
}

/** The striped side of a page block. */
export function pageEdgeTexture() {
  const c = canvas(64, 256), g = c.getContext('2d');
  g.fillStyle = '#efe4c8'; g.fillRect(0, 0, 64, 256);
  const r = rng(9);
  for (let y = 0; y < 256; y += 2) { g.fillStyle = `rgba(120,95,50,${0.10 + r() * 0.22})`; g.fillRect(0, y, 64, 1); }
  const t = tex(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; return t;
}

export function makeCover(subject, maxAniso) {
  const art = subject === 'geography' ? geographyCover() : historyCover();
  for (const t of [art.color, art.mr, art.bump]) t.anisotropy = maxAniso;
  return { ...art, endpaper: endpaper(subject) };
}
