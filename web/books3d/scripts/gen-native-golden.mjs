// Writes PalabraTests/Books/Native/native-golden.json: numbers produced by the REAL Three.js scene code (book3d.js, app.js
// framing, tween.js easings, pagetex.js pagination) that the native Swift scene must reproduce.
//   cd web/books3d && npm ci && node scripts/gen-native-golden.mjs
// The measure used for pagination is `String(text).length * 14` (UTF-16 units), the same fake the JS tests use, so the Swift
// side can reproduce it exactly without a font.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// --- a canvas that accepts and ignores everything (cover.js and pagetex.js draw into canvases when a Book3D is built) ----
const noop = new Proxy(function () {}, {
  get: (_t, key) => (key === Symbol.toPrimitive ? () => 0 : noop),
  apply: () => noop,
  set: () => true,
});
globalThis.document = {
  createElement: () => ({ width: 0, height: 0, style: {}, getContext: () => noop, ownerDocument: globalThis.document }),
};

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..', '..');
const { Book3D, PW, PH, COVER_T } = await import('../src/book3d.js');
const { App } = await import('../src/app.js');
const { ease } = await import('../src/tween.js');
const { buildLibrary } = await import('../src/data.js');
const { paginate } = await import('../src/pagetex.js');

const round = (x, d = 6) => Math.round(x * 10 ** d) / 10 ** d;
const flat = (arr, d = 6) => Array.from(arr, (v) => round(v, d));
const vec = (v) => [round(v.x, 9), round(v.y, 9), round(v.z, 9)];

// ---------------------------------------------------------------------------------------------------------------------
// Constants (so the Swift side can assert it copied them correctly)
const constants = { PW, PH, COVER_T, SX: 28, SZ: 8, BLOCK_COLS: 14, GUTTER_DIP: 0.03, FOV: 32 };

// ---------------------------------------------------------------------------------------------------------------------
// Leaves
function makeBook(n, flippedBefore, bulk = 0.26) {
  const book = new Book3D({ subject: 'history', rtl: false, leafCount: n, bulk, maxAniso: 4 });
  book.leaves.forEach((l, i) => { l.p = i < flippedBefore ? 1 : 0; l.peek = 0; l.grabZ = 0.5; l.dirty = true; });
  book._layoutDirty = true;
  return book;
}

const leaves = [];
const targets = [[1, [0]], [3, [0, 1, 2]], [8, [0, 4, 7]]];
for (const [n, ks] of targets) {
  for (const k of ks) {
    const variants = [];
    for (const p of [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]) variants.push({ p, peek: 0, grabZ: 0.5 });
    variants.push({ p: 0.5, peek: 0, grabZ: 0.2 }, { p: 0.5, peek: 0, grabZ: 0.9 });
    variants.push({ p: 0, peek: 0.6, grabZ: 0.2 }, { p: 0, peek: 0.6, grabZ: 0.9 }, { p: 0.3, peek: 0.6, grabZ: 0.5 });
    for (const v of variants) {
      const book = makeBook(n, k);
      const leaf = book.leaves[k];
      leaf.p = v.p; leaf.peek = v.peek; leaf.grabZ = v.grabZ; leaf.dirty = true;
      book._layoutDirty = true;
      book.layout();
      const rest = book._restY(k);
      leaves.push({
        leafCount: n, index: k, bulk: 0.26, p: v.p, peek: v.peek, grabZ: v.grabZ,
        restYr: round(rest.yr, 9), restYl: round(rest.yl, 9),
        surfaceYRight: round(book.surfaceY(1), 9), surfaceYLeft: round(book.surfaceY(-1), 9),
        positions: flat(leaf.posAttr.array), normals: flat(leaf.geo.attributes.normal.array),
      });
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Page blocks and ribbon
const blocks = [];
for (const [n, counts] of [[1, [0, 1]], [3, [0, 1, 3]], [8, [0, 3, 8]]]) {
  for (const flipped of counts) {
    const book = makeBook(n, flipped);
    book.layout();
    const dump = (mesh) => ({
      visible: mesh.visible, scaleX: mesh.scale.x,
      positions: flat(mesh.geometry.attributes.position.array), uvs: flat(mesh.geometry.attributes.uv.array),
    });
    blocks.push({ leafCount: n, flipped, bulk: 0.26, right: dump(book.blockR), left: dump(book.blockL) });
  }
}
const ribbons = [];
for (const open of [0, 0.7, 1]) {
  const book = makeBook(3, 1);
  book.setCoverOpen(open);
  ribbons.push({ leafCount: 3, flipped: 1, coverOpen: open, visible: book.ribbon.visible, positions: flat(book.ribbonGeo.attributes.position.array) });
}

// ---------------------------------------------------------------------------------------------------------------------
// Framing: the real App methods, run on a fake `this` (no WebGL needed)
function fakeApp({ w, h, top, bottom, rtl = false, focus = false, pan = 0, surfaceY = 0.1 }) {
  const app = Object.create(App.prototype);
  Object.assign(app, {
    fov: 32, size: { w, h }, insets: { top, bottom }, pan, _panLimit: 0, _pxPerZ: 1,
    state: { focus }, cur: { data: { rtl }, book: { surfaceY: () => surfaceY } },
  });
  app.captured = null;
  app.moveCamera = (t) => { app.captured = t; };
  return app;
}
// The HUD insets (SceneHUD / BooksSceneScreen.InsetKey) for the cases below.
function insets({ landscape, reading, focus, recall }) {
  const safeTop = landscape ? 0 : 59, safeBottom = landscape ? 21 : 34;
  const top = safeTop + (reading ? (focus ? 12 : 60) : (landscape ? 16 : 56));
  const bottom = safeBottom + (reading ? (focus ? 76 : (recall ? 150 : 92)) : (landscape ? 100 : 120));
  return { top, bottom };
}
const sizes = [[393, 852, false], [852, 393, true], [430, 932, false]];
const frames = [];
const menus = [];
for (const [w, h, landscape] of sizes) {
  const m = insets({ landscape, reading: false, focus: false, recall: false });
  const app = fakeApp({ w, h, top: m.top, bottom: m.bottom });
  app.frameMenu(false);
  app._applyCamera = function () {}; // not used by frameMenu(false) capture
  menus.push({ w, h, insetTop: m.top, insetBottom: m.bottom, pos: vec(app.captured.pos), look: vec(app.captured.look) });
  // opening a book: the cover pose
  for (const rtl of [false, true]) {
    const a = fakeApp({ w, h, top: m.top, bottom: m.bottom, rtl });
    const pose = a._frameRect(rtl ? -PW / 2 : PW / 2, 0, PW / 2 + 0.2, PH / 2 + 0.1, 62, 0.3);
    frames.push({ kind: 'cover', w, h, insetTop: m.top, insetBottom: m.bottom, rtl, pos: vec(pose.pos), look: vec(pose.look) });
  }
  for (const focus of [false, true]) {
    for (const recall of [false, true]) {
      if (focus && recall) continue;
      const ins = insets({ landscape, reading: true, focus, recall });
      for (const rtl of [false, true]) {
        for (const page of [0, 1, 2, 5]) {
          for (const pan of [-99, 0, 0.2]) {
            const surfaceY = 0.1 + 0.01 * page;
            const a = fakeApp({ w, h, top: ins.top, bottom: ins.bottom, rtl, focus, pan, surfaceY });
            const t = a._readTarget(page, focus);
            frames.push({
              kind: 'reading', w, h, insetTop: ins.top, insetBottom: ins.bottom, rtl, focus, page, pan, surfaceY,
              pos: vec(t.pos), look: vec(t.look), panLimit: round(a._panLimit, 9), pxPerZ: round(a._pxPerZ, 9), panAfter: round(a.pan, 9),
            });
          }
        }
      }
    }
  }
}
// Menu slots (position and rotation of the two books on the desk) for wide and tall screens.
const menuSlots = [];
for (const [w, h] of [[393, 852], [852, 393]]) {
  const app = fakeApp({ w, h, top: 0, bottom: 0 });
  const entries = [0, 1].map((i) => {
    const e = { data: { rtl: i === 0 }, hover: 0 };
    e.book = {
      group: { position: { set(x, y, z) { e.pos = [x, y, z]; } }, rotation: { set(x, y, z) { e.rot = [x, y, z]; }, y: 0 }, visible: true },
      setCoverOpen() {}, leaves: [], layout() {},
    };
    return e;
  });
  app.entries = entries; app._ensureTextures = () => {}; app.invalidate = () => {};
  app._menuLayout();
  menuSlots.push({ w, h, wide: app._menuWide, slots: entries.map((e) => ({ x: e.pos[0], y: e.pos[1], z: e.pos[2], ry: e.rot[1] })) });
}

// ---------------------------------------------------------------------------------------------------------------------
// Easings
const eases = [];
for (const name of ['linear', 'inOut', 'out', 'inOutSine', 'outBack']) {
  for (const t of [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]) eases.push({ name, t, value: round(ease[name](t), 12) });
}

// ---------------------------------------------------------------------------------------------------------------------
// Pagination with a fixed fake measure (UTF-16 length * 14)
const resources = join(root, 'Palabra', 'Resources', 'Books');
const catalogue = JSON.parse(readFileSync(join(resources, 'textbooks.json'), 'utf8'));
const lessons = {};
for (const b of catalogue.books) for (const c of b.chapters) for (const l of c.lessons) lessons[l.file] = JSON.parse(readFileSync(join(resources, l.file + '.json'), 'utf8'));
const library = buildLibrary({ catalogue, lessons });
const measure = (text) => String(text).length * 14;
const pagination = [];
for (const book of library.books) {
  for (const scale of [0.96, 1.1, 1.26, 1.42]) {
    for (const page of book.pages) {
      const phys = paginate(page, { measure, subject: book.subject, rtl: book.rtl, scale });
      pagination.push({
        bookId: book.id, scale, pageId: page.id,
        parts: phys.map((p) => ({
          id: p.id, baseId: p.baseId, part: p.part, parts: p.parts, scale: round(p.scale, 9),
          blocks: p.blocks.map((b) => ({ index: b.index, height: round(b.layout.height, 4) })),
        })),
      });
    }
  }
}

const out = { constants, leaves, blocks, ribbons, frames, menus, menuSlots, eases, pagination };
const outPath = join(root, 'PalabraTests', 'Books', 'Native', 'native-golden.json');
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(out));
const counts = Object.fromEntries(Object.entries(out).map(([k, v]) => [k, Array.isArray(v) ? v.length : Object.keys(v).length]));
console.log('wrote', outPath, `${(JSON.stringify(out).length / 1024).toFixed(0)} KB`, counts);
