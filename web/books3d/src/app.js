// The scene controller: menu with two books on a desk, a transition into reading, real page turns,
// tools (magnifying glass, bookmark, reading ruler), Focus Mode, Magnifying-Glass recall, and the bridge to the app.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { buildLibrary, resumeIndex } from './data.js';
import { Tweens, ease } from './tween.js';
import { paginate, drawPage, makeMeasure, RecallState, PAGE_W, PAGE_H, paletteFor } from './pagetex.js';
import { Book3D, PW, PH, COVER_T } from './book3d.js';
import { Room } from './desk.js';
import { Magnifier, Bookmark, Ruler } from './tools.js';

const TEXT_SCALE = { '-1': 0.96, '0': 1.1, '1': 1.26, '2': 1.42 };
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;

export class App {
  constructor(canvas, post) {
    this.canvas = canvas;
    this.post = post || (() => {});
    this.tweens = new Tweens();
    this.state = {
      mode: 'menu', bookId: null, page: 0, pageCount: 0, basePageId: null, tool: null, focus: false,
      recall: false, level: 1, bookmark: null, textSize: 0, dark: false, ready: false, loading: true,
      canNext: false, canPrev: false, revealed: false, problems: [],
    };
    this.recall = new RecallState(1);
    this.insets = { top: 0, bottom: 0 }; this.pan = -99; this._panLimit = 0; this._pxPerZ = 1;
    this.reduced = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    this.lowPower = /iPhone|iPad|Android/i.test(navigator.userAgent) || (navigator.hardwareConcurrency || 8) <= 4;
    this.entries = [];           // per book: {data, book3d, pages:[phys], textures, hits}
    this.cur = null;
    this.dirty = true;
    this.pointer = { x: 0, y: 0, inside: false };
    this.hoverBook = null;
    this.camState = { pos: new THREE.Vector3(0, 6, 6), look: new THREE.Vector3() };
    this.fov = 32;
    this.pageTex = new Map();
    this.pageHits = new Map();
    this.images = {};
    this.lensTexKey = null;
    this._boot();
  }

  // -------------------------------------------------------------------------------------------
  _boot() {
    const renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, powerPreference: 'high-performance', alpha: false });
    this.renderer = renderer;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, this.lowPower ? 2 : 2.5));
    renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.NeutralToneMapping; renderer.toneMappingExposure = 1.0;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());

    this.scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    this.envTex = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.scene.environment = this.envTex;
    this.scene.environmentIntensity = 0.55;
    this.camera = new THREE.PerspectiveCamera(this.fov, 1, 0.05, 40);
    this.camera.position.copy(this.camState.pos);

    // Lights
    this.hemi = new THREE.HemisphereLight(0xfff3dd, 0xb08a60, 0.5); this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight(0xfff0d4, 2.4);
    this.sun.position.set(-3.4, 3.8, 2.4); this.sun.castShadow = true;
    const sh = this.sun.shadow; const smap = this.lowPower ? 1024 : 2048; sh.mapSize.set(smap, smap);
    sh.camera.left = -3.2; sh.camera.right = 3.2; sh.camera.top = 3.4; sh.camera.bottom = -3.4; sh.camera.near = 1; sh.camera.far = 14;
    sh.bias = -0.0004; sh.normalBias = 0.018; sh.radius = 4;
    this.scene.add(this.sun, this.sun.target);
    this.lampLight = new THREE.SpotLight(0xffc880, 0, 12, 0.85, 0.75, 1.6);
    this.lampLight.position.set(-1.4, 3.4, -1.6); this.lampLight.target.position.set(0, 0, 0);
    this.lampLight.castShadow = true; this.lampLight.shadow.mapSize.set(smap, smap); this.lampLight.shadow.bias = -0.0005; this.lampLight.shadow.normalBias = 0.02; this.lampLight.shadow.radius = 5;
    this.scene.add(this.lampLight, this.lampLight.target);

    this.room = new Room(this.maxAniso); this.scene.add(this.room.group);
    this.lens = new Magnifier(this.maxAniso); this.bookmark = new Bookmark(); this.ruler = new Ruler();
    this.tools = { lens: this.lens, bookmark: this.bookmark, ruler: this.ruler };
    for (const t of Object.values(this.tools)) { this.room.props.add(t.group); t.group.traverse((o) => { if (o.isMesh) { o.castShadow = o.castShadow || false; } }); }
    for (const t of Object.values(this.tools)) t.group.traverse((o) => { if (o.isMesh && o !== this.lens.glass && o !== this.lens.sheen) { o.castShadow = true; o.receiveShadow = true; } });

    for (const t of Object.values(this.tools)) t.group.visible = false;
    this.raycaster = new THREE.Raycaster();
    this._bindEvents();
    this.setAppearance(false);
    this.resize();
    this._loop = this._loop.bind(this);
    this._last = performance.now();
    requestAnimationFrame(this._loop);
  }

  setAppearance(dark) {
    this.state.dark = dark;
    this.room.setAppearance(dark);
    this.scene.background = new THREE.Color(dark ? 0x141311 : 0xe9e4d8);
    this.hemi.intensity = dark ? 0.16 : 0.42;
    this.hemi.color.set(dark ? 0x9fb0d0 : 0xfff3dd);
    this.sun.intensity = dark ? 0.35 : 2.1; this.sun.color.set(dark ? 0x8aa0cc : 0xfff7ea);
    this.lampLight.intensity = dark ? 34 : 0; this.lampLight.visible = dark; this.lampLight.castShadow = dark && this.quality !== 'saver';
    this.scene.environmentIntensity = dark ? 0.22 : 0.55;
    this.renderer.toneMappingExposure = dark ? 1.1 : 0.92;
    this.invalidate(); this.emit();
  }

  invalidate() { this.dirty = true; }

  // -------------------------------------------------------------------------------------------
  // Loading
  async load(payload, options = {}) {
    await this._fonts();
    if (options.reducedMotion !== undefined) this.reduced = options.reducedMotion;
    this.tweens.scale = this.reduced ? 0.001 : 1;
    this.images = {};
    this.payload = payload;
    this.textSize = payload.preferences ? payload.preferences.textSize || 0 : 0;
    this.state.textSize = this.textSize;
    this.recall.setLevel(payload.preferences && payload.preferences.recallLevel || 1);
    this.state.level = this.recall.level;
    this.progress = payload.progress || {};
    this.bookmarks = payload.bookmarks || {};
    if (payload.preferences && payload.preferences.sceneQuality) this.setQuality(payload.preferences.sceneQuality);
    this._rebuild();
    this.state.loading = false; this.state.ready = true;
    this._menuLayout(false);
    this.frameMenu(false);
    this.emit(); this.post({ type: 'ready' });
  }

  async _fonts() {
    if (this._fontsReady) return;
    try {
      await Promise.all([
        document.fonts.load('400 40px Amiri', 'ابت'), document.fonts.load('700 40px Amiri', 'ابت'),
        document.fonts.load('400 40px Amiri', 'Ab1'), document.fonts.load('700 40px Amiri', 'Ab1'),
      ]);
    } catch (e) { /* fall back to system fonts */ }
    this._fontsReady = true;
  }

  _rebuild() {
    for (const e of this.entries) { this.scene.remove(e.book.group); e.book.dispose(); }
    for (const t of this.pageTex.values()) t.tex.dispose();
    this.pageTex.clear(); this.pageHits.clear();
    const lib = buildLibrary(this.payload);
    this.state.problems = lib.problems;
    const measureCtx = document.createElement('canvas').getContext('2d');
    const measure = makeMeasure(measureCtx);
    this.measure = measure;
    this.entries = lib.books.map((data) => {
      const pages = [];
      for (const bp of data.pages) {
        for (const phys of paginate(bp, { measure, rtl: data.rtl, scale: TEXT_SCALE[String(this.textSize)] || 1, subject: data.subject })) pages.push(phys);
      }
      pages.forEach((p, i) => { p.number = i + 1; });
      const leafCount = Math.max(1, Math.ceil(pages.length / 2));
      const book = new Book3D({ subject: data.subject, rtl: data.rtl, leafCount, bulk: data.subject === 'geography' ? 0.18 : 0.26, maxAniso: this.maxAniso });
      this.scene.add(book.group);
      book.group.traverse((o) => { o.userData.bookId = data.id; });
      return { data, pages, book, empty: pages.length === 0 };
    });
  }

  // -------------------------------------------------------------------------------------------
  // Page textures
  _texKey(entry, i, kind) { return `${entry.data.id}:${i}:${kind}`; }

  _pageTexture(entry, i) {
    const key = this._texKey(entry, i, 'base');
    let rec = this.pageTex.get(key);
    if (!rec) {
      const canvas = document.createElement('canvas'); canvas.width = PAGE_W; canvas.height = PAGE_H;
      const tex = new THREE.CanvasTexture(canvas);
      tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = this.maxAniso; tex.minFilter = THREE.LinearMipmapLinearFilter; tex.generateMipmaps = true;
      rec = { canvas, tex }; this.pageTex.set(key, rec);
      this._drawInto(entry, i, rec, false);
    }
    return rec;
  }

  _drawInto(entry, i, rec, revealAll) {
    const phys = entry.pages[i] || null;
    const hits = drawPage(rec.canvas, phys, {
      measure: this.measure, face: i % 2 === 0 ? 'front' : 'back', rtl: entry.data.rtl, subject: entry.data.subject,
      recall: this.recall, revealAll, images: this.images,
    });
    if (!revealAll) this.pageHits.set(this._texKey(entry, i, 'base'), hits);
    rec.tex.needsUpdate = true;
  }

  redrawVisible() {
    const e = this.cur; if (!e) return;
    for (const [key, rec] of this.pageTex) {
      if (!key.startsWith(e.data.id + ':') || !key.endsWith(':base')) continue;
      const i = Number(key.split(':')[1]);
      this._drawInto(e, i, rec, false);
    }
    this._lensRefresh(true);
    this.invalidate();
  }

  /** Assign textures to the leaves around page `i`; free the ones far away. */
  _ensureTextures(entry, i) {
    const n = entry.pages.length;
    const want = new Set();
    for (let k = i - 3; k <= i + 3; k++) if (k >= -1 && k <= n) want.add(k);
    for (let leaf = 0; leaf < entry.book.n; leaf++) {
      for (const face of ['front', 'back']) {
        const pi = leaf * 2 + (face === 'front' ? 0 : 1);
        if (want.has(pi) && pi < n) entry.book.setLeafTexture(leaf, face, this._pageTexture(entry, pi).tex);
        else if (pi >= n && want.has(pi)) entry.book.setLeafTexture(leaf, face, this._pageTexture(entry, pi).tex); // blank end sheet
        else entry.book.setLeafTexture(leaf, face, null);
      }
    }
    // drop textures that are not assigned any more
    for (const [key, rec] of [...this.pageTex]) {
      if (!key.startsWith(entry.data.id + ':') || !key.endsWith(':base')) continue;
      const pi = Number(key.split(':')[1]);
      if (Math.abs(pi - i) > 6) { rec.tex.dispose(); this.pageTex.delete(key); this.pageHits.delete(key); }
    }
  }

  // -------------------------------------------------------------------------------------------
  // Menu
  _isWide() { return this.size.w / this.size.h > 1.15; }

  _menuLayout() {
    const wide = this._menuWide = this._isWide();
    const slots = wide ? [
      { x: -0.82, z: 0.1, ry: 0.12 },   // first book: left
      { x: 0.86, z: -0.05, ry: -0.1 },  // second book: right
    ] : [
      { x: -0.2, z: 0.85, ry: 0.10 },   // first book: near
      { x: 0.25, z: -1.05, ry: -0.08 }, // second book: behind
    ];
    this.entries.forEach((e, i) => {
      const s = slots[i] || { x: i * 1.2, z: -i, ry: 0 };
      e.menu = { x: s.x, z: s.z, ry: e.data.rtl ? Math.PI + s.ry * -1 : s.ry };
      // A right-to-left book lies with its spine on the right: that is the mirrored model, so no extra turn is needed.
      e.menu.ry = s.ry;
      e.hover = 0;
      e.book.group.position.set(s.x, 0, s.z); e.book.group.rotation.set(0, s.ry, 0);
      e.book.group.visible = true;
      e.book.setCoverOpen(0);
      for (const l of e.book.leaves) { l.p = 0; l.dirty = true; }
      e.book.layout();
      this._ensureTextures(e, 0);
    });
    this.invalidate();
  }

  // -------------------------------------------------------------------------------------------
  // Camera framing
  _frameParams() {
    const w = this.size.w, h = this.size.h;
    return { aspect: w / h, usableTop: this.insets.top, usableBottom: this.insets.bottom, h };
  }

  /** Camera position/look that frames a rectangle on the desk plane (world coords). */
  _frameRect(cx, cz, hw, hh, pitchDeg, y = 0) {
    const fov = THREE.MathUtils.degToRad(this.fov);
    const aspect = this.size.w / this.size.h;
    const usable = clamp(1 - (this.insets.top + this.insets.bottom) / this.size.h, 0.35, 1);
    const a = THREE.MathUtils.degToRad(pitchDeg);
    const tanV = Math.tan(fov / 2);
    const dW = hw / (tanV * aspect * 0.98);
    const dH = (hh * Math.sin(a) + 0.12 * Math.cos(a)) / (tanV * usable);
    const d = Math.max(dW, dH);
    const look = new THREE.Vector3(cx, y, cz);
    const pos = new THREE.Vector3(cx, y + d * Math.sin(a), cz + d * Math.cos(a));
    return { pos, look };
  }

  frameMenu(animate = true) {
    const t = this._isWide() ? this._frameRect(0.0, 0.05, 2.1, 1.2, 52) : this._frameRect(0.0, -0.1, 1.55, 1.95, 56);
    this.moveCamera(t, animate ? 1.1 : 0);
  }

  _readTarget(i, focus = this.state.focus) {
    const e = this.cur; const rtlSign = e.data.rtl ? -1 : 1;
    const onRight = i % 2 === 0;
    const cx = rtlSign * (onRight ? PW / 2 : -PW / 2);
    const y = e.book.surfaceY(onRight ? 1 : -1);
    const pitch = focus ? 66 : 58;
    if (this._isWide()) {
      // Landscape is short, so a whole page would be tiny: fill about half the width with the page (the neighbouring page
      // stays visible beside it) and let the reader scroll down it.
      const frac = focus ? 0.56 : 0.5;
      const hw = (PW / 2 + 0.03) / frac;
      const t0 = this._frameRect(cx, 0, hw, 0.05, pitch, y);
      const fov = THREE.MathUtils.degToRad(this.fov);
      const usable = clamp(1 - (this.insets.top + this.insets.bottom) / this.size.h, 0.35, 1);
      const d = t0.pos.distanceTo(t0.look);
      const halfZ = (d * Math.tan(fov / 2) * usable) / Math.sin(THREE.MathUtils.degToRad(pitch));
      this._panLimit = Math.max(0, PH / 2 - halfZ + 0.06);
      this._pxPerZ = (this.size.h * usable) / (2 * halfZ);
      this.pan = clamp(this.pan, -this._panLimit, this._panLimit);
      return this._frameRect(cx, this.pan, hw, 0.05, pitch, y);
    }
    this._panLimit = 0; this.pan = 0;
    const fit = focus ? 0.5 * 1.02 : 0.5 * 1.1;
    return this._frameRect(cx, 0, fit, PH / 2 + 0.02, pitch, y);
  }

  moveCamera(target, duration = 0.9) {
    const from = { pos: this.camState.pos.clone(), look: this.camState.look.clone() };
    if (this._camTween) this.tweens.cancel(this._camTween);
    if (duration <= 0) { this.camState.pos.copy(target.pos); this.camState.look.copy(target.look); this._applyCamera(); return; }
    this._camTween = this.tweens.add({
      duration, ease: ease.inOut,
      onUpdate: (t) => { this.camState.pos.lerpVectors(from.pos, target.pos, t); this.camState.look.lerpVectors(from.look, target.look, t); this._applyCamera(); },
    });
  }

  _applyCamera() {
    this.camera.position.copy(this.camState.pos);
    this.camera.lookAt(this.camState.look);
    const { w, h } = this.size;
    const shift = (this.insets.top - this.insets.bottom) / 2; // content moves toward the free area
    this.camera.setViewOffset(w, h, 0, shift, w, h);
    this.camera.updateMatrixWorld();
    this.invalidate();
  }

  resize() {
    const w = this.canvas.clientWidth || window.innerWidth, h = this.canvas.clientHeight || window.innerHeight;
    this.size = { w, h };
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
    if (this.state.mode === 'reading' && this.cur) this.moveCamera(this._readTarget(this.state.page), 0);
    else if (this.state.mode === 'menu') { if (this._isWide() !== this._menuWide) this._menuLayout(); this.frameMenu(false); }
    this._applyCamera();
  }

  /** 'standard' or 'saver' (lower pixel density, no shadows: easier on the battery). */
  setQuality(q) {
    this.quality = q === 'saver' ? 'saver' : 'standard';
    const saver = this.quality === 'saver';
    this.renderer.setPixelRatio(saver ? 1.25 : Math.min(window.devicePixelRatio || 1, this.lowPower ? 2 : 2.5));
    this.renderer.shadowMap.enabled = !saver;
    this.sun.castShadow = !saver;
    if (saver) this.lampLight.castShadow = false; else this.lampLight.castShadow = !!this.state.dark;
    this.scene.traverse((o) => { if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => { m.needsUpdate = true; }); });
    this.resize(); this.invalidate();
  }

  setInsets(top, bottom) {
    this.insets = { top: top || 0, bottom: bottom || 0 };
    this.resize();
  }

  // -------------------------------------------------------------------------------------------
  // Opening and closing a book
  openBook(bookId, pageId) {
    if (this.state.mode !== 'menu') return;
    const entry = this.entries.find((e) => e.data.id === bookId);
    if (!entry || entry.empty) { this.post({ type: 'empty', bookId }); return; }
    this.cur = entry;
    this.state.mode = 'opening'; this.state.bookId = bookId;
    for (const t of Object.values(this.tools)) { t.group.visible = true; }
    const resume = pageId ? this._indexOfBase(entry, pageId) : resumeIndex({ pages: entry.pages.map((p) => ({ id: p.baseId, lessonId: p.bookPage.lessonId })) }, (this.progress[bookId] || {}).lastPageID);
    const startPage = clamp(resume < 0 ? 0 : resume, 0, entry.pages.length - 1);
    this.state.page = startPage; this.state.pageCount = entry.pages.length;
    this._setLeavesInstant(entry, startPage);
    this._ensureTextures(entry, startPage);
    // other books slide off to the side
    for (const e of this.entries) if (e !== entry) { const from = e.book.group.position.clone(); this.tweens.add({ duration: 0.7, ease: ease.inOut, onUpdate: (t) => { e.book.group.position.set(from.x + (this.size.w > this.size.h ? 3.5 : 0), from.y, lerp(from.z, from.z - 3.4, t)); this.invalidate(); } }); }
    const b = entry.book.group; const from = { p: b.position.clone(), ry: b.rotation.y };
    this.tweens.add({
      duration: 0.8, ease: ease.inOut,
      onUpdate: (t) => { b.position.set(lerp(from.p.x, 0, t), Math.sin(t * Math.PI) * 0.35, lerp(from.p.z, 0, t)); b.rotation.y = lerp(from.ry, 0, t); this.invalidate(); },
    });
    // look at the closed cover first, then open it while the camera comes down onto the page
    const cover = this._frameRect(entry.data.rtl ? -PW / 2 : PW / 2, 0, PW / 2 + 0.2, PH / 2 + 0.1, 62, 0.3);
    this.moveCamera(cover, 0.8);
    this.tweens.add({
      duration: 1.15, delay: 0.55, ease: ease.inOut,
      onUpdate: (t) => { entry.book.setCoverOpen(t); this.invalidate(); },
      onDone: () => { this.state.mode = 'reading'; this.state.page = startPage; this._afterNavigate(true); },
    });
    this.moveCameraDelayed(this._readTarget(startPage, false), 0.55, 1.2);
    this.emit();
  }

  moveCameraDelayed(target, delay, duration) { this.tweens.add({ duration: 0.0001, delay, onUpdate: () => {}, onDone: () => this.moveCamera(target, duration) }); }

  closeBook() {
    if (this.state.mode !== 'reading' || !this.cur) return;
    const entry = this.cur;
    this._returnTools();
    this.setFocus(false, true);
    this.state.mode = 'closing';
    const flips = entry.book.leaves.filter((l) => l.p > 0.5);
    flips.forEach((l, k) => this._animateLeaf(entry, l.index, 0, 0.45, Math.min(0.5, k * 0.05) , false));
    const wait = flips.length ? Math.min(0.5, flips.length * 0.05) + 0.45 : 0;
    this.tweens.add({
      duration: 0.9, delay: wait, ease: ease.inOut,
      onUpdate: (t) => { entry.book.setCoverOpen(1 - t); this.invalidate(); },
      onDone: () => {
        const e = this.cur; this.cur = null;
        for (const t of Object.values(this.tools)) t.group.visible = false;
        this.state.mode = 'menu'; this.state.bookId = null; this.state.page = 0;
        this._menuTransitionBack(e); this.emit();
      },
    });
    this.moveCameraDelayed(this._frameRect(entry.data.rtl ? -PW / 2 : PW / 2, 0, PW / 2 + 0.2, PH / 2 + 0.1, 62, 0.3), wait, 0.9);
    this.emit();
  }

  _menuTransitionBack(entry) {
    const e = entry;
    this.entries.forEach((x) => {
      const from = x.book.group.position.clone(); const fry = x.book.group.rotation.y;
      this.tweens.add({
        duration: 0.9, ease: ease.inOut,
        onUpdate: (t) => { x.book.group.position.set(lerp(from.x, x.menu.x, t), Math.sin(t * Math.PI) * (x === e ? 0.3 : 0), lerp(from.z, x.menu.z, t)); x.book.group.rotation.y = lerp(fry, x.menu.ry, t); this.invalidate(); },
      });
    });
    this.frameMenu(true);
  }

  _setLeavesInstant(entry, page) {
    const f = Math.ceil(page / 2);
    entry.book.leaves.forEach((l) => { l.p = l.index < f ? 1 : 0; l.dirty = true; });
    entry.book._layoutDirty = true; entry.book.layout();
  }

  _indexOfBase(entry, baseId) { return entry.pages.findIndex((p) => p.baseId === baseId); }

  // -------------------------------------------------------------------------------------------
  // Page navigation. Page i is the front (even) or back (odd) of leaf floor(i/2).
  next() { const i = this.state.page; this.goToPage(i + 1, true); }
  prev() { const i = this.state.page; this.goToPage(i - 1, true); }

  goToPage(target, user = false) {
    const e = this.cur; if (!e || this.state.mode !== 'reading') return;
    target = clamp(target, 0, e.pages.length - 1);
    if (target === this.state.page) return;
    this._closeTerm();
    const wantF = Math.ceil(target / 2);
    const curF = e.book.leaves.filter((l) => l.p >= 0.5).length;
    const dir = wantF > curF ? 1 : -1;
    const diff = Math.abs(wantF - curF);
    this.state.page = target; this.pan = -99;
    this._ensureTextures(e, target);
    if (diff > 0) {
      const stagger = Math.min(0.1, 0.55 / Math.max(1, diff));
      const dur = diff > 2 ? 0.55 : 0.85;
      for (let k = 0; k < diff; k++) {
        const li = dir > 0 ? curF + k : curF - 1 - k;
        this._animateLeaf(e, li, dir > 0 ? 1 : 0, dur, k * stagger, true);
      }
    }
    this.moveCamera(this._readTarget(target), diff > 0 ? 0.9 : 0.7);
    this._afterNavigate(false);
  }

  _animateLeaf(entry, index, to, duration, delay, withSound) {
    const leaf = entry.book.leaves[index]; if (!leaf) return;
    if (leaf.tw) this.tweens.cancel(leaf.tw);
    const from = leaf.p;
    leaf.tw = this.tweens.add({
      duration, delay, ease: ease.inOutSine,
      onUpdate: (t) => { entry.book.setLeafProgress(index, lerp(from, to, t)); entry.book.layout(); this.invalidate(); },
      onDone: () => { entry.book.setLeafProgress(index, to); entry.book.layout(); leaf.tw = null; this.invalidate(); },
    });
  }

  _afterNavigate(first) {
    const e = this.cur; if (!e) return;
    const i = this.state.page;
    const phys = e.pages[i];
    this.state.basePageId = phys.baseId;
    this.state.canPrev = i > 0; this.state.canNext = i < e.pages.length - 1;
    this.state.revealed = this.recall.isPageRevealed(phys.id);
    this._ensureTextures(e, i);
    this.post({ type: 'visit', bookId: e.data.id, pageId: phys.baseId, page: i + 1, pageCount: e.pages.length });
    this._lensRefresh(true);
    this.emit(); this.invalidate();
  }

  // -------------------------------------------------------------------------------------------
  // Recall (memorisation) mode
  setRecall(enabled) { if (this.recall.setEnabled(!!enabled)) { this.state.recall = this.recall.enabled; this.state.revealed = false; this.redrawVisible(); this.emit(); } }
  setLevel(level) {
    const l = clamp(Number(level) || 1, 1, 3);
    if (this.recall.setLevel(l)) { this.state.level = l; this.post({ type: 'preference', recallLevel: l }); this.state.revealed = false; this.redrawVisible(); this.emit(); }
  }
  togglePageReveal() {
    const e = this.cur; if (!e) return; const id = e.pages[this.state.page].id;
    if (this.recall.isPageRevealed(id)) this.recall.hidePage(id); else this.recall.revealPage(id);
    this.state.revealed = this.recall.isPageRevealed(id); this.redrawVisible(); this.emit();
  }
  setTextSize(size) {
    const s = clamp(Number(size) || 0, -1, 2);
    if (s === this.textSize) return;
    this.textSize = s; this.state.textSize = s; this.post({ type: 'preference', textSize: s });
    const keepBase = this.state.basePageId; const wasReading = this.state.mode === 'reading' ? this.cur.data.id : null;
    if (wasReading) { this._returnTools(); }
    this._rebuild(); this._menuLayout();
    if (wasReading) {
      const entry = this.entries.find((x) => x.data.id === wasReading); this.cur = entry;
      const idx = Math.max(0, this._indexOfBase(entry, keepBase));
      this.state.page = idx; this.state.pageCount = entry.pages.length;
      entry.book.group.position.set(0, 0, 0); entry.book.group.rotation.y = 0;
      for (const e of this.entries) if (e !== entry) e.book.group.position.set(0, 0, -6);
      this._setLeavesInstant(entry, idx); entry.book.setCoverOpen(1);
      this._afterNavigate(false); this.moveCamera(this._readTarget(idx), 0);
    }
    this.emit();
  }

  // -------------------------------------------------------------------------------------------
  // Focus Mode: the desk and its tools step out of view; the page fills the screen.
  setFocus(on, silent = false) {
    if (this.state.focus === !!on) return;
    this.state.focus = !!on;
    const from = this._propsOpacity ?? 1; const to = on ? 0 : 1;
    this.tweens.add({
      duration: 0.7, ease: ease.inOut,
      onUpdate: (t) => { this._setPropsOpacity(lerp(from, to, t)); },
    });
    if (this.cur && this.state.mode === 'reading') this.moveCamera(this._readTarget(this.state.page, on), 0.9);
    if (!silent) this.emit();
  }
  _setPropsOpacity(v) {
    this._propsOpacity = v;
    const vis = v > 0.02;
    this.room.props.visible = vis || this.state.tool !== null;
    this.room.props.children.forEach((c) => {
      const isTool = Object.values(this.tools).some((t) => t.group === c);
      if (isTool) { c.visible = true; return; }
      c.visible = vis; c.position.y = c.userData.baseY !== undefined ? c.userData.baseY : (c.userData.baseY = c.position.y);
      c.position.y = c.userData.baseY - (1 - v) * 0.6;
    });
    this.room.group.children.forEach((c) => { if (c.geometry && c !== this.room.props) { /* desk stays: it is the ground */ } });
    // resting tools sink and vanish with the desk objects
    for (const [name, t] of Object.entries(this.tools)) {
      if (this.state.tool === name) continue;
      t.group.visible = vis;
      t.group.position.y = t.restPos.y - (1 - v) * 0.6;
    }
    this.invalidate();
  }

  // -------------------------------------------------------------------------------------------
  // Tools
  setTool(name) {
    if (this.state.mode !== 'reading') return;
    if (name === this.state.tool) name = null;
    const prev = this.state.tool;
    if (prev) this._stowTool(prev);
    this.state.tool = name || null;
    if (name) this._useTool(name);
    this.emit(); this.invalidate();
  }

  _returnTools() { if (this.state.tool) { this._stowTool(this.state.tool); this.state.tool = null; } }

  _stowTool(name) {
    const t = this.tools[name]; const g = t.group;
    const fromP = g.position.clone(); const fromR = new THREE.Euler().copy(g.rotation); const fq = new THREE.Quaternion().setFromEuler(fromR);
    const toQ = new THREE.Quaternion().setFromEuler(t.restRot);
    const toP = t.restPos.clone(); if (this.state.focus) toP.y -= 0.6;
    if (name === 'lens') { this.lens.setMagnifying(false, false); }
    if (name === 'ruler') this._setBand(false);
    if (name === 'bookmark') { this._bookmarkPlaced = false; this._setBookmark(null); }
    this.tweens.add({
      duration: 0.8, ease: ease.inOut,
      onUpdate: (k) => { g.position.lerpVectors(fromP, toP, k); g.position.y += Math.sin(k * Math.PI) * 0.35; g.quaternion.slerpQuaternions(fq, toQ, k); this.invalidate(); },
      onDone: () => { if (this.state.focus) g.visible = false; },
    });
  }

  _useTool(name) {
    const e = this.cur; const t = this.tools[name]; const g = t.group; g.visible = true;
    const fromP = g.position.clone(); const fq = g.quaternion.clone();
    const side = this.state.page % 2 === 0 ? 1 : -1;
    const rs = e.data.rtl ? -1 : 1;
    const surf = e.book.surfaceY(side);
    let toP, toQ, extra = null;
    if (name === 'lens') {
      toP = new THREE.Vector3(rs * side * PW * 0.5, surf + 0.26, 0.1);
      toQ = new THREE.Quaternion().setFromEuler(new THREE.Euler(-0.2, 0, 0));
      this.lensPos = new THREE.Vector2(toP.x, toP.z);
      this.lens.setMagnifying(true, true);
      this._lensRefresh(true);
    } else if (name === 'ruler') {
      const z = -0.25; toP = new THREE.Vector3(rs * side * PW * 0.5, surf + 0.012, z);
      toQ = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, 0));
      this.rulerZ = z; this._setBand(true);
    } else {
      // The card slides in at the head of the page, its tassel hanging over the fore edge.
      toP = new THREE.Vector3(rs * side * (PW - 0.16), surf + 0.01, -PH / 2 + 0.17);
      toQ = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, 0));
      this._placeBookmark();
    }
    this.tweens.add({
      duration: 0.85, ease: ease.inOut,
      onUpdate: (k) => { g.position.lerpVectors(fromP, toP, k); g.position.y += Math.sin(k * Math.PI) * 0.45; g.quaternion.slerpQuaternions(fq, toQ, k); this.invalidate(); },
      onDone: () => { if (name === 'lens') this._lensRefresh(true); },
    });
  }

  _placeBookmark() {
    const e = this.cur; const phys = e.pages[this.state.page];
    this.bookmarks[e.data.id] = phys.baseId; this.state.bookmark = phys.baseId;
    this.post({ type: 'bookmark', bookId: e.data.id, pageId: phys.baseId });
  }
  _setBookmark(id) {
    const e = this.cur; if (!e) return;
    this.bookmarks[e.data.id] = id; this.state.bookmark = id;
    this.post({ type: 'bookmark', bookId: e.data.id, pageId: id });
  }

  _setBand(on) {
    const e = this.cur; if (!e) return;
    for (const l of e.book.leaves) for (const m of [l.front, l.back]) m.material.userData.band.value.x = 0;
    this.bandOn = on;
    if (on) this._updateBand();
    this.invalidate();
  }
  _updateBand() {
    const e = this.cur; if (!e || !this.bandOn) return;
    const i = this.state.page; const leaf = e.book.leaves[Math.floor(i / 2)];
    const mesh = i % 2 === 0 ? leaf.front : leaf.back;
    const v = 1 - (this.rulerZ + PH / 2) / PH; // texture v of the band centre
    const half = (this.ruler.width / 2) / PH;
    for (const l of e.book.leaves) for (const m of [l.front, l.back]) m.material.userData.band.value.x = 0;
    mesh.material.userData.band.value.set(1, v, half * 1.15, 0);
  }

  _lensRefresh(force) {
    const e = this.cur; if (!e || this.state.tool !== 'lens' || !this.lensPos) return;
    const rs = e.data.rtl ? -1 : 1;
    // local book x of the lens centre decides which page is magnified
    const localX = this.lensPos.x * rs;
    const side = localX >= 0 ? 1 : -1;
    const i = side > 0 ? 2 * Math.floor(this.state.page / 2) + 0 : 2 * Math.floor((this.state.page + 1) / 2) - 1;
    const pageIndex = side > 0 ? Math.min(2 * Math.ceil(this.state.page / 2), e.pages.length) : 2 * Math.ceil(this.state.page / 2) - 1;
    const key = `${e.data.id}:${pageIndex}:lens:${this.recall.level}:${this.recall.enabled}:${this.recall.overrides.size}:${this.recall.revealedPages.size}`;
    if (!force && key === this.lensTexKey) return;
    this.lensTexKey = key;
    // High-resolution, everything revealed: the lens shows what is hidden beneath it.
    if (!this._lensCanvas) { this._lensCanvas = document.createElement('canvas'); this._lensCanvas.width = 2048; this._lensCanvas.height = Math.round(2048 * PAGE_H / PAGE_W); this._lensTex = new THREE.CanvasTexture(this._lensCanvas); this._lensTex.colorSpace = THREE.SRGBColorSpace; this._lensTex.anisotropy = this.maxAniso; }
    const has = pageIndex >= 0 && pageIndex < e.pages.length;
    if (has) {
      const phys = e.pages[pageIndex];
      drawPage(this._lensCanvas, phys, { measure: this.measure, face: pageIndex % 2 === 0 ? 'front' : 'back', rtl: e.data.rtl, subject: e.data.subject, recall: this.recall, revealAll: true, images: this.images });
      this._lensTex.needsUpdate = true;
    }
    const u = this.lens.uniforms;
    u.tPage.value = this._lensTex; u.uHas.value = has ? 1 : 0; u.uSide.value = side; u.uRtl.value = e.data.rtl ? 1 : 0;
    u.uPlaneY.value = e.book.surfaceY(side);
    this.invalidate();
  }

  // -------------------------------------------------------------------------------------------
  // Terms
  _openTerm(id) {
    const phys = this.cur.pages[this.state.page]; const def = phys.glossary && phys.glossary[id];
    if (!def) return;
    this.state.term = { id, term: def.term, definition: def.definition };
    this.post({ type: 'term', id, term: def.term, definition: def.definition }); this.emit();
  }
  _closeTerm() { if (this.state.term) { this.state.term = null; this.post({ type: 'termClose' }); this.emit(); } }

  // -------------------------------------------------------------------------------------------
  // Pointer input
  _bindEvents() {
    const c = this.canvas;
    const move = (e) => {
      const r = c.getBoundingClientRect();
      this.pointer.x = ((e.clientX - r.left) / r.width) * 2 - 1; this.pointer.y = -(((e.clientY - r.top) / r.height) * 2 - 1);
      this.pointer.px = e.clientX - r.left; this.pointer.py = e.clientY - r.top;
    };
    c.addEventListener('pointerdown', (e) => { c.setPointerCapture(e.pointerId); move(e); this._down(e); });
    c.addEventListener('pointermove', (e) => { move(e); this._move(e); });
    c.addEventListener('pointerup', (e) => { move(e); this._up(e); });
    c.addEventListener('wheel', (e) => { if (this._panLimit > 0 && this.state.mode === 'reading') { e.preventDefault(); this._panBy(this.pan + e.deltaY / (this._pxPerZ || 1)); } }, { passive: false });
    c.addEventListener('pointercancel', (e) => { this._cancel(e); });
    c.addEventListener('pointerleave', () => { this.pointer.inside = false; this._hover(null); });
    c.addEventListener('keydown', (e) => this._key(e)); c.tabIndex = 0;
    window.addEventListener('resize', () => this.resize());
  }

  _ray() { this.raycaster.setFromCamera(new THREE.Vector2(this.pointer.x, this.pointer.y), this.camera); return this.raycaster; }

  _bookAt() {
    const rc = this._ray();
    for (const e of this.entries) {
      if (e.empty && false) continue;
      const hit = rc.intersectObject(e.book.group, true)[0];
      if (hit) return { entry: e, hit };
    }
    return null;
  }

  _toolAt() {
    const rc = this._ray(); const groups = Object.values(this.tools).map((t) => t.group).filter((g) => g.visible);
    const hit = rc.intersectObjects(groups, true)[0];
    if (!hit) return null;
    let o = hit.object; while (o && !o.userData.tool) o = o.parent;
    return o ? { name: o.userData.tool, hit } : null;
  }

  /** The page surface under the pointer: {entry, pageIndex, u, v (texture px), local (book-local point), mesh}. */
  _pageAt() {
    const e = this.cur; if (!e) return null;
    const rc = this._ray();
    const hit = rc.intersectObjects(e.book.pageMeshes(), false)[0];
    if (!hit || !hit.uv) return null;
    const leaf = hit.object.userData.leaf; const face = hit.object.userData.face;
    const pageIndex = leaf * 2 + (face === 'front' ? 0 : 1);
    let u = hit.uv.x; if (e.data.rtl) u = 1 - u;
    return { pageIndex, px: u * PAGE_W, py: (1 - hit.uv.y) * PAGE_H, hit, leaf, face };
  }

  /** Intersect the pointer ray with the page plane at the top of a stack (book-local x/z). */
  _planePoint(side) {
    const e = this.cur; const y = e.book.surfaceY(side);
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -y);
    const p = new THREE.Vector3();
    if (!this._ray().ray.intersectPlane(plane, p)) return null;
    return p; // world == book space when the book sits at the origin
  }

  _hover(h) {
    const id = h ? h.entry.data.id : null;
    if (id === this.hoverBook) return;
    this.hoverBook = id; this.invalidate();
  }

  _down(ev) {
    this.drag = { x: ev.clientX, y: ev.clientY, t: performance.now(), moved: false, mode: null, touch: ev.pointerType !== 'mouse' };
    if (this.state.mode === 'menu') { const b = this._bookAt(); this.drag.book = b ? b.entry : null; this._hover(b); return; }
    if (this.state.mode !== 'reading') return;
    const tool = this._toolAt();
    if (tool && this.state.tool !== tool.name && !(this.state.tool === 'lens' && tool.name === 'lens')) { this.drag.tool = tool.name; return; }
    if (this.state.tool === 'lens' && tool && tool.name === 'lens') { this.drag.mode = 'lens'; return; }
    if (this.state.tool === 'ruler' && tool && tool.name === 'ruler') { this.drag.mode = 'ruler'; return; }
    if (this.state.tool === 'bookmark' && tool && tool.name === 'bookmark') { this.drag.tool = 'bookmark-remove'; return; }
    const pg = this._pageAt();
    this.drag.page = pg;
    const side = this.state.page % 2 === 0 ? 1 : -1;
    const pp = this._planePoint(pg && pg.leaf !== undefined ? (pg.face === 'front' ? 1 : -1) : side);
    if (pp) {
      const rs = this.cur.data.rtl ? -1 : 1; this.drag.x0 = pp.x * rs;
      // press on the outer 22% of a page: grab it to turn
      const px = pg ? pg.px / PAGE_W : 0.5;
      const gutterLeft = pg ? ((pg.face === 'front') !== this.cur.data.rtl) : true;
      const nearOuter = gutterLeft ? px > 0.78 : px < 0.22;
      if (pg && nearOuter) this.drag.edge = true;
    }
    if (this.state.tool === 'lens' && !this.drag.edge) this.drag.mode = 'lens';
  }

  _move(ev) {
    const d = this.drag;
    if (!d) { this._hoverMove(ev); return; }
    const dx = ev.clientX - d.x, dy = ev.clientY - d.y;
    if (!d.moved && Math.hypot(dx, dy) > 8) d.moved = true;
    if (this.state.mode !== 'reading') return;
    if (d.mode === 'lens') { this._moveLens(d.touch); return; }
    if (d.mode === 'ruler') { this._moveRuler(); return; }
    if (d.mode === 'turn') { this._dragTurn(); return; }
    if (d.mode === 'pan') { this._panBy(d.pan0 - dy / (this._pxPerZ || 1)); return; }
    if (d.moved && !d.mode && !d.tool) {
      const horizontal = Math.abs(dx) > Math.abs(dy) * 1.1;
      if (!d.edge && !horizontal && this._panLimit > 0 && this.state.tool !== 'lens') { d.mode = 'pan'; d.pan0 = this.pan; return; }
      if (d.edge || (horizontal && this.state.tool !== 'lens')) this._beginTurn(dx);
    }
  }

  _panBy(z) {
    if (!this.cur || this.state.mode !== 'reading') return;
    this.pan = clamp(z, -this._panLimit, this._panLimit);
    this.moveCamera(this._readTarget(this.state.page), 0);
  }

  _hoverMove(ev) {
    this.pointer.inside = true;
    if (this.state.mode === 'menu') { this._hover(ev.pointerType === 'mouse' ? this._bookAt() : null); return; }
    if (this.state.mode !== 'reading') return;
    if (this.state.tool === 'lens' && ev.pointerType === 'mouse') { this._moveLens(false); }
    // hover over a page's outer edge lifts its corner
    const pg = this._pageAt(); let peekLeaf = null;
    if (pg && ev.pointerType === 'mouse') {
      const gutterLeft = (pg.face === 'front') !== this.cur.data.rtl; const px = pg.px / PAGE_W;
      const near = gutterLeft ? px > 0.8 : px < 0.2;
      const isCurrent = Math.floor(this.state.page / 2) === pg.leaf || Math.floor((this.state.page + 1) / 2) - 1 === pg.leaf;
      if (near && isCurrent && this._canTurn(pg)) peekLeaf = { leaf: pg.leaf, z: pg.py / PAGE_H };
    }
    this._setPeek(peekLeaf);
  }

  _canTurn(pg) { const e = this.cur; if (pg.face === 'front') return pg.leaf * 2 + 1 < e.pages.length + 1 && pg.leaf < e.book.n && e.book.leaves[pg.leaf].p === 0; return e.book.leaves[pg.leaf].p === 1; }

  _setPeek(p) {
    const e = this.cur; if (!e) return;
    for (const l of e.book.leaves) {
      const want = p && p.leaf === l.index ? 1 : 0;
      if (p && p.leaf === l.index) e.book.setGrab(l.index, clamp(p.z, 0, 1));
      if (Math.abs(l.peek - want) > 0.001) { l.peek += (want - l.peek) * 0.25; if (Math.abs(l.peek - want) < 0.01) l.peek = want; e.book.setPeek(l.index, l.peek); this._peekAnim = true; }
    }
    if (e.book.leaves.some((l) => l.dirty)) { e.book.layout(); this.invalidate(); }
  }

  _moveLens(touch) {
    const e = this.cur; if (!e) return;
    const pp = this._planePoint(this.lensPos && this.lensPos.x * (e.data.rtl ? -1 : 1) >= 0 ? 1 : -1);
    if (!pp) return;
    const off = touch ? -0.38 : 0; // keep the lens clear of a finger
    const lim = PW * 1.0;
    const x = clamp(pp.x, -lim * 1.02, lim * 1.02), z = clamp(pp.z + off, -PH / 2 + 0.05, PH / 2 - 0.05);
    this.lensPos.set(x, z);
    const side = (x * (e.data.rtl ? -1 : 1)) >= 0 ? 1 : -1;
    const surf = e.book.surfaceY(side);
    this.lens.group.position.set(x, surf + 0.26, z);
    this._lensRefresh(false);
    this.invalidate();
  }

  _moveRuler() {
    const e = this.cur; const side = this.state.page % 2 === 0 ? 1 : -1;
    const pp = this._planePoint(side); if (!pp) return;
    this.rulerZ = clamp(pp.z, -PH / 2 + 0.1, PH / 2 - 0.1);
    this.ruler.group.position.z = this.rulerZ;
    this._updateBand(); this.invalidate();
  }

  _beginTurn(dx) {
    const e = this.cur; const d = this.drag;
    const rs = e.data.rtl ? -1 : 1;
    // dragging toward the spine turns forward from a right page; away from it turns back from a left page
    const side = d.page ? (d.page.face === 'front' ? 1 : -1) : (this.state.page % 2 === 0 ? 1 : -1);
    const f = e.book.leaves.filter((l) => l.p >= 0.5).length;
    let leaf;
    if (side > 0) { leaf = f; if (leaf >= e.book.n) return; } else { leaf = f - 1; if (leaf < 0) return; }
    if (e.book.leaves[leaf].tw) return;
    // Page reading order: from the right page you can only turn forward; from the left page only back.
    d.mode = 'turn'; d.leaf = leaf; d.side = side; d.p0 = e.book.leaves[leaf].p;
    d.lastP = d.p0; d.lastT = performance.now(); d.v = 0;
    this._setPeek(null); this._closeTerm();
    const pp = this._planePoint(side); d.x0 = pp ? pp.x * rs : 0;
    this._dragTurn();
  }

  _dragTurn() {
    const e = this.cur; const d = this.drag; const rs = e.data.rtl ? -1 : 1;
    const pp = this._planePoint(d.side); if (!pp) return;
    const x = pp.x * rs;
    const tip = d.side > 0 ? PW - (d.x0 - x) : -PW + (x - d.x0);
    let p = Math.acos(clamp(tip / PW, -1, 1)) / Math.PI;
    p = d.side > 0 ? clamp(p, 0, 1) : clamp(p, 0, 1);
    const pg = this._pageAt();
    e.book.setGrab(d.leaf, d.page ? clamp(d.page.py / PAGE_H, 0, 1) : 0.8);
    const now = performance.now(); d.v = (p - d.lastP) / Math.max(1, now - d.lastT) * 1000; d.lastP = p; d.lastT = now;
    e.book.setLeafProgress(d.leaf, p); e.book.layout(); this.invalidate();
  }

  _up(ev) {
    const d = this.drag; this.drag = null; if (!d) return;
    if (this.state.mode === 'menu') {
      const b = this._bookAt();
      if (b && d.book && b.entry === d.book && !d.moved) this.openBook(b.entry.data.id);
      this._hover(ev.pointerType === 'mouse' ? b : null); return;
    }
    if (this.state.mode !== 'reading') return;
    const e = this.cur;
    if (d.mode === 'turn') {
      const leaf = e.book.leaves[d.leaf]; const p = leaf.p;
      const forward = d.side > 0;
      let complete = forward ? (p > 0.42 || d.v > 0.9) : (p < 0.58 || d.v < -0.9);
      if (forward && d.v < -0.9) complete = false; if (!forward && d.v > 0.9) complete = false;
      const to = complete ? (forward ? 1 : 0) : (forward ? 0 : 1);
      this._animateLeaf(e, d.leaf, to, 0.5 * Math.abs(to - p) + 0.18, 0, true);
      if (complete) {
        // forward from a right page lands on the next left page; back from a left page lands on the previous right page
        const f = Math.ceil(this.state.page / 2);
        const target = forward ? 2 * f + 1 : 2 * (f - 1);
        const clampT = clamp(target, 0, e.pages.length - 1);
        this.state.page = clampT; this._ensureTextures(e, clampT);
        this.moveCamera(this._readTarget(clampT), 0.8); this._afterNavigate(false);
      }
      return;
    }
    if (d.tool === 'bookmark-remove') { this.setTool('bookmark'); return; }
    if (d.tool) { if (!d.moved) this.setTool(d.tool); return; }
    if (d.mode === 'lens' || d.mode === 'ruler') { if (!d.moved) this._tapPage(); return; }
    if (!d.moved) { this._tapPage(); return; }
  }

  _cancel() { this.drag = null; this._setPeek(null); }

  _tapPage() {
    const pg = this._pageAt(); if (!pg) { this._closeTerm(); return; }
    const e = this.cur; const key = this._texKey(e, pg.pageIndex, 'base');
    const hits = this.pageHits.get(key) || [];
    for (let i = hits.length - 1; i >= 0; i--) {
      const h = hits[i];
      if (pg.px >= h.x && pg.px <= h.x + h.w && pg.py >= h.y && pg.py <= h.y + h.h) {
        if (h.kind === 'term') { this._openTerm(h.id); return; }
        if (h.kind === 'recall') { const phys = e.pages[pg.pageIndex]; this.recall.toggle(h.key, phys.id); this.state.revealed = this.recall.isPageRevealed(phys.id); this.redrawVisible(); this.emit(); return; }
      }
    }
    this._closeTerm();
    // tapping the page body turns when nothing else was hit and no tool is out
  }

  _key(e) {
    if (e.key === 'ArrowRight') { (this.cur && this.cur.data.rtl) ? this.prev() : this.next(); }
    else if (e.key === 'ArrowLeft') { (this.cur && this.cur.data.rtl) ? this.next() : this.prev(); }
    else if (e.key === 'Escape') { if (this.state.focus) this.setFocus(false); else this.closeBook(); }
  }

  // -------------------------------------------------------------------------------------------
  emit() {
    const s = this.state; const e = this.cur;
    this.post({ type: 'state', state: {
      mode: s.mode, bookId: s.bookId, page: s.page + 1, pageCount: s.pageCount, basePageId: s.basePageId, tool: s.tool, focus: s.focus,
      recall: this.recall.enabled, level: this.recall.level, revealed: s.revealed, bookmark: e ? (this.bookmarks[e.data.id] || null) : null,
      textSize: s.textSize, dark: s.dark, canNext: s.canNext, canPrev: s.canPrev, rtl: e ? e.data.rtl : false,
      title: e ? e.data.title : null, subject: e ? e.data.subject : null, problems: s.problems.length,
      books: this.entries.map((x) => ({ id: x.data.id, title: x.data.title, subject: x.data.subject, pages: x.pages.length, rtl: x.data.rtl })),
    } });
    if (this.onState) this.onState(this.snapshot());
  }
  snapshot() {
    const s = this.state; const e = this.cur;
    return { mode: s.mode, bookId: s.bookId, page: s.page + 1, pageCount: s.pageCount, tool: s.tool, focus: s.focus, recall: this.recall.enabled, level: this.recall.level,
      revealed: s.revealed, canNext: s.canNext, canPrev: s.canPrev, textSize: s.textSize, dark: s.dark, rtl: e ? e.data.rtl : false, title: e ? e.data.title : null,
      books: this.entries.map((x) => ({ id: x.data.id, title: x.data.title, subject: x.data.subject, pages: x.pages.length })), term: s.term || null,
      bookmark: e ? (this.bookmarks[e.data.id] || null) : null, basePageId: s.basePageId };
  }

  command(c) {
    switch (c.name) {
      case 'openBook': this.openBook(c.bookId, c.pageId); break;
      case 'closeBook': this.closeBook(); break;
      case 'next': this.next(); break;
      case 'prev': this.prev(); break;
      case 'goto': { const e = this.cur; if (e) this.goToPage(e.pages.findIndex((p) => p.baseId === c.pageId), true); break; }
      case 'setRecall': this.setRecall(c.enabled); break;
      case 'setLevel': this.setLevel(c.level); break;
      case 'togglePageReveal': this.togglePageReveal(); break;
      case 'setTool': this.setTool(c.tool); break;
      case 'setFocus': this.setFocus(c.on); break;
      case 'setTextSize': this.setTextSize(c.size); break;
      case 'setInsets': this.setInsets(c.top, c.bottom); break;
      case 'setAppearance': this.setAppearance(!!c.dark); break;
      case 'setQuality': this.setQuality(c.quality); break;
      case 'closeTerm': this._closeTerm(); break;
      case 'hoverBook': break;
      default: break;
    }
  }

  // -------------------------------------------------------------------------------------------
  _loop(now) {
    requestAnimationFrame(this._loop);
    const dt = Math.min(0.05, (now - this._last) / 1000); this._last = now;
    const busy = this.tweens.active;
    if (busy) this.tweens.update(dt);
    if (this.state.mode === 'menu') this._hoverStep(dt);
    if (this.state.mode === 'reading' && this._peekAnim) { this._peekSettle(); }
    if (this.dirty || busy) {
      this.dirty = false;
      this._frame();
    }
  }

  _hoverStep(dt) {
    let moving = false;
    for (const e of this.entries) {
      const target = this.hoverBook === e.data.id ? 1 : 0;
      const k = e.hover + (target - e.hover) * Math.min(1, dt * 9);
      if (Math.abs(k - e.hover) > 0.0005) moving = true;
      e.hover = Math.abs(target - k) < 0.002 ? target : k;
      if (this.state.mode === 'menu') {
        const g = e.book.group;
        g.position.set(e.menu.x, e.hover * 0.07, e.menu.z + e.hover * 0.1);
        g.rotation.y = e.menu.ry + e.hover * (e.menu.ry > 0 ? -0.05 : 0.05);
        g.rotation.x = -e.hover * 0.045;
      }
    }
    if (moving) this.invalidate();
  }

  _peekSettle() {
    const e = this.cur; if (!e) return; let any = false;
    for (const l of e.book.leaves) { if (l.peek > 0 && !(this._peekTarget === l.index)) { /* decays through _setPeek calls */ } if (l.peek > 0.002 && this.pointer.inside === false) { l.peek *= 0.7; e.book.setPeek(l.index, l.peek); any = true; } }
    if (any) { e.book.layout(); this.invalidate(); } else this._peekAnim = false;
  }

  _frame() {
    if (this.lens && this.state.tool === 'lens') {
      const u = this.lens.uniforms; const e = this.cur;
      if (e) {
        this.scene.updateMatrixWorld(true);
        const inv = new THREE.Matrix4().copy(e.book.body.matrixWorld).invert();
        u.uWorldToBook.value.copy(inv);
        u.uCamBook.value.copy(this.camera.position).applyMatrix4(inv);
        const rs = e.data.rtl ? -1 : 1;
        // Centre of the glass, followed along the real view ray down to the page plane
        const gc = new THREE.Vector3(); this.lens.glass.getWorldPosition(gc); gc.applyMatrix4(inv);
        const cam = u.uCamBook.value;
        const side0 = gc.x >= 0 ? 1 : -1;
        const py = e.book.surfaceY(side0);
        const k = (py - cam.y) / (gc.y - cam.y);
        const cx = cam.x + (gc.x - cam.x) * k, cz = cam.z + (gc.z - cam.z) * k;
        u.uCentre.value.set(cx, 0, cz);
        const side = cx >= 0 ? 1 : -1;
        if (u.uSide.value !== side) this._lensRefresh(true);
        u.uPlaneY.value = e.book.surfaceY(side);
        u.uTone.value = this.state.dark ? 0.78 : 0.92;
      }
    }
    // keep the sun's shadow frustum on the active book
    this.renderer.render(this.scene, this.camera);
  }
}
