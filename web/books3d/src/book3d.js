// A real 3D book: hinged cover boards, a spine, page blocks with visible thickness, and leaves whose
// geometry bends around the binding while they turn. Logical layout is left-to-right (spine at x = 0,
// right page at x > 0); a right-to-left book is the same model mirrored with its textures flipped back.
import * as THREE from 'three';
import { makeCover, pageEdgeTexture } from './cover.js';
import { PAGE_W, PAGE_H } from './pagetex.js';

export const PW = 1.0;          // page width
export const PH = PAGE_H / PAGE_W * PW; // page height (≈ 1.42)
export const COVER_T = 0.04;
const OVER_X = 0.035, OVER_Z = 0.045;
const SX = 28, SZ = 8;
const BLOCK_COLS = 14;
const GUTTER_DIP = 0.03;

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

export class Book3D {
  /**
   * @param {object} o {subject, rtl, leafCount, bulk, maxAniso}
   */
  constructor(o) {
    this.subject = o.subject;
    this.rtl = !!o.rtl;
    this.n = Math.max(1, o.leafCount);
    this.bulk = o.bulk ?? 0.22;
    this.group = new THREE.Group();
    this.body = new THREE.Group();   // mirrored for right-to-left books
    this.group.add(this.body);
    if (this.rtl) this.body.scale.x = -1;
    this.cover = makeCover(o.subject, o.maxAniso || 4);
    this.edgeTex = pageEdgeTexture();
    this.coverP = 0;                 // 0 closed .. 1 open
    this.leaves = [];
    this.flat = new THREE.Group();   // leaves
    this.body.add(this.flat);
    this._build();
    this.layout();
  }

  // -------------------------------------------------------------------------------------------
  _build() {
    const { cover } = this;
    const total = this.totalThickness();
    // Back cover (static)
    const backMats = [this.cloth(), this.cloth(), this.endMat(), this.outerMat(true), this.cloth(), this.cloth()];
    this.back = new THREE.Mesh(new THREE.BoxGeometry(PW + OVER_X, COVER_T, PH + OVER_Z * 2), backMats);
    this.back.position.set((PW + OVER_X) / 2 - 0.0, COVER_T / 2, 0);
    this.back.castShadow = this.back.receiveShadow = true;
    this.body.add(this.back);

    // Front cover board on a pivot at the spine
    this.pivot = new THREE.Group();
    const frontMats = [this.cloth(), this.cloth(), this.outerMat(false), this.endMat(), this.cloth(), this.cloth()];
    this.front = new THREE.Mesh(new THREE.BoxGeometry(PW + OVER_X, COVER_T, PH + OVER_Z * 2), frontMats);
    this.front.position.set((PW + OVER_X) / 2, COVER_T / 2, 0);
    this.front.castShadow = this.front.receiveShadow = true;
    this.pivot.add(this.front);
    this.body.add(this.pivot);

    // Spine: half pipe wrapping the binding edge
    const R = total / 2;
    const spineGeo = new THREE.CylinderGeometry(R, R, PH + OVER_Z * 2, 28, 1, true, Math.PI, Math.PI);
    spineGeo.rotateX(Math.PI / 2);
    this.spineMat = this.spineMaterial();
    this.spine = new THREE.Mesh(spineGeo, this.spineMat);
    this.spine.position.set(0, R, 0);
    this.spine.castShadow = true;
    this.body.add(this.spine);
    this.spineR = R;
    // Raised bands on the spine (history) or a gold label (atlas)
    this.bands = [];
    const bandMat = new THREE.MeshStandardMaterial({ color: 0xc9992f, metalness: 0.9, roughness: 0.3 });
    const nb = this.subject === 'geography' ? 2 : 4;
    for (let i = 0; i < nb; i++) {
      const z = (-0.42 + i * (0.84 / Math.max(1, nb - 1))) * PH;
      const geo = new THREE.TorusGeometry(R + 0.004, 0.006, 6, 24, Math.PI);
      const m = new THREE.Mesh(geo, bandMat);
      m.rotation.set(0, 0, Math.PI / 2 + 0);
      m.position.set(0, R, z);
      m.rotation.z = Math.PI / 2;
      this.body.add(m);
      this.bands.push(m);
    }

    // Page blocks (the visible thickness of the paper): lofted so their top follows the gutter dip of the leaf above
    const edge = new THREE.MeshStandardMaterial({ map: this.edgeTex, roughness: 0.95, side: THREE.DoubleSide });
    this.blockR = this._makeBlock(edge); this.blockL = this._makeBlock(edge);
    for (const b of [this.blockR, this.blockL]) { b.castShadow = b.receiveShadow = true; this.body.add(b); }

    // Leaves
    for (let i = 0; i < this.n; i++) this.leaves.push(this._makeLeaf(i));

    // Ribbon marker (sewn into the head of the spine, hanging out the bottom)
    const rib = new THREE.PlaneGeometry(0.03, 1.0, 1, 12);
    this.ribbonGeo = rib;
    this.ribbon = new THREE.Mesh(rib, new THREE.MeshStandardMaterial({ color: this.subject === 'geography' ? 0xc9742a : 0x8c1f2c, roughness: 0.55, side: THREE.DoubleSide }));
    this.ribbon.castShadow = true; this.body.add(this.ribbon);
  }

  totalThickness() { return COVER_T * 2 + this.bulk; }

  cloth() { return new THREE.MeshStandardMaterial({ color: this.cover.cloth, roughness: 0.85 }); }
  endMat() { return new THREE.MeshStandardMaterial({ map: this.cover.endpaper, roughness: 0.9 }); }
  outerMat(back) {
    if (back) return new THREE.MeshStandardMaterial({ color: this.cover.cloth, roughness: 0.8 });
    const c = this.cover;
    const m = new THREE.MeshPhysicalMaterial({ map: c.color, metalnessMap: c.mr, roughnessMap: c.mr, metalness: 1, roughness: 1, bumpMap: c.bump, bumpScale: 1.6, clearcoat: this.subject === 'history' ? 0.25 : 0, clearcoatRoughness: 0.5 });
    // Art is drawn readable; flip u for a mirrored (right-to-left) book, and match Box top-face uv orientation.
    for (const t of [c.color, c.mr, c.bump]) { t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.RepeatWrapping; t.repeat.set(this.rtl ? -1 : 1, 1); t.offset.set(this.rtl ? 1 : 0, 0); }
    return m;
  }
  spineMaterial() {
    const c = this.cover;
    return new THREE.MeshPhysicalMaterial({ color: c.cloth, roughness: 0.55, metalness: 0.0, bumpMap: c.bump, bumpScale: 1.2, side: THREE.DoubleSide });
  }

  // -------------------------------------------------------------------------------------------
  _makeLeaf(index) {
    const nx = SX + 1, nz = SZ + 1;
    const pos = new Float32Array(nx * nz * 3);
    const nor = new Float32Array(nx * nz * 3);
    const uvF = new Float32Array(nx * nz * 2);
    const uvB = new Float32Array(nx * nz * 2);
    for (let iz = 0; iz < nz; iz++) for (let ix = 0; ix < nx; ix++) {
      const k = iz * nx + ix;
      const u = ix / SX; const v = 1 - iz / SZ;
      uvF[k * 2] = u; uvF[k * 2 + 1] = v;
      uvB[k * 2] = 1 - u; uvB[k * 2 + 1] = v;
    }
    const idx = [];
    for (let iz = 0; iz < SZ; iz++) for (let ix = 0; ix < SX; ix++) {
      const a = iz * nx + ix, b = a + 1, c = a + nx, d = c + 1;
      // viewed from +y, with +z toward the viewer: counter-clockwise
      idx.push(a, c, b, b, c, d);
    }
    const gF = new THREE.BufferGeometry(); const gB = new THREE.BufferGeometry();
    const posAttr = new THREE.BufferAttribute(pos, 3); posAttr.setUsage(THREE.DynamicDrawUsage);
    const norAttr = new THREE.BufferAttribute(nor, 3); norAttr.setUsage(THREE.DynamicDrawUsage);
    for (const [g, uv] of [[gF, uvF], [gB, uvB]]) {
      g.setAttribute('position', posAttr); g.setAttribute('normal', norAttr);
      g.setAttribute('uv', new THREE.BufferAttribute(uv, 2)); g.setIndex(idx);
    }
    const mkMat = (side) => {
      const m = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.92, side });
      m.userData.band = { value: new THREE.Vector4(0, 0, 0, 0) }; // x: active, y: centre v, z: half height v
      m.onBeforeCompile = (sh) => {
        sh.uniforms.uBand = m.userData.band;
        sh.fragmentShader = sh.fragmentShader
          .replace('#include <common>', '#include <common>\nuniform vec4 uBand;')
          .replace('#include <map_fragment>', `#include <map_fragment>
          #ifdef USE_MAP
          if (uBand.x > 0.5) { float d = abs(vMapUv.y - uBand.y); float inBand = 1.0 - smoothstep(uBand.z, uBand.z + 0.012, d); diffuseColor.rgb *= mix(0.42, 1.0, inBand); }
          #endif`);
      };
      return m;
    };
    const front = new THREE.Mesh(gF, mkMat(THREE.FrontSide));
    const back = new THREE.Mesh(gB, mkMat(THREE.BackSide));
    for (const m of [front, back]) { m.castShadow = true; m.receiveShadow = true; m.frustumCulled = false; this.flat.add(m); }
    front.userData.leaf = index; front.userData.face = 'front';
    back.userData.leaf = index; back.userData.face = 'back';
    return { index, p: 0, peek: 0, grabZ: 0.5, front, back, posAttr, norAttr, geo: gF, texFront: null, texBack: null, dirty: true };
  }

  /** Assigns the canvas texture shown on a face (null = blank paper). */
  setLeafTexture(index, face, texture) {
    const leaf = this.leaves[index];
    if (!leaf) return;
    const mesh = face === 'front' ? leaf.front : leaf.back;
    if (texture) {
      // Textures are drawn readable; right-to-left books are mirrored, so flip them back.
      texture.wrapS = THREE.RepeatWrapping;
      texture.repeat.x = this.rtl ? -1 : 1; texture.offset.x = this.rtl ? 1 : 0;
      texture.needsUpdate = true;
    }
    mesh.material.map = texture; mesh.material.needsUpdate = true;
    mesh.material.color.set(texture ? 0xffffff : 0xf0e6cd);
  }

  // -------------------------------------------------------------------------------------------
  setLeafProgress(index, p) { const l = this.leaves[index]; if (l.p !== p) { l.p = p; l.dirty = true; this._layoutDirty = true; } }
  setPeek(index, peek) { const l = this.leaves[index]; if (Math.abs(l.peek - peek) > 1e-4) { l.peek = peek; l.dirty = true; } }
  setGrab(index, z) { this.leaves[index].grabZ = z; }
  setCoverOpen(p) { this.coverP = p; this._layoutDirty = true; this.layout(); }

  /** Height of the top surface of leaf i when resting on the right / left stack, given the other leaves' progress. */
  _restY(i) {
    let right = 0, left = 0;
    for (let j = 0; j < this.n; j++) { const pj = this.leaves[j].p; if (j >= i) right += 1 - pj; if (j <= i) left += pj; }
    const k = this.bulk / this.n;
    return { yr: COVER_T + k * right, yl: COVER_T + k * left };
  }

  layout() {
    const k = this.bulk / this.n;
    let sumR = 0, sumL = 0;
    for (const l of this.leaves) { sumR += 1 - l.p; sumL += l.p; }
    const hR = k * sumR, hL = k * sumL;
    const open = this.coverP;
    // Page blocks
    this._placeBlock(this.blockR, hR, 1);
    this._placeBlock(this.blockL, hL, -1);
    // Front cover: rotates about the spine, pivot height follows the stack it ends up on
    const closedY = COVER_T + this.bulk;
    this.pivot.position.set(0, lerp(closedY, COVER_T, smooth(0, 1, open)), 0);
    this.pivot.rotation.z = open * Math.PI;
    // The spine stands up when the book is closed and folds down under the boards when it is open.
    const fold = smooth(0.0, 1.0, open);
    this.spine.scale.set(lerp(1, 0.35, fold), lerp(1, 0.1, fold), 1);
    this.spine.position.y = this.spineR * lerp(1, 0.1, fold);
    for (const b of this.bands) { b.scale.set(lerp(1, 0.35, fold), lerp(1, 0.1, fold), 1); b.position.y = this.spineR * lerp(1, 0.1, fold); }
    // Leaves
    for (const l of this.leaves) if (l.dirty || this._layoutDirty) this._deform(l);
    this._layoutDirty = false;
    // Ribbon
    this._ribbon();
  }

  _makeBlock(material) {
    const M = BLOCK_COLS;
    const nv = (M + 1) * 2 * 2 + 4;
    const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), uv = new Float32Array(nv * 2);
    const idx = [];
    let v = 0;
    const d = (PH - 0.012) / 2;
    const face = (z, nz) => {
      const base = v;
      for (let i = 0; i <= M; i++) { for (let r = 0; r < 2; r++) { nor[(v) * 3 + 2] = nz; uv[v * 2] = (i / M) * 4; v++; } }
      for (let i = 0; i < M; i++) { const a = base + i * 2, b = a + 1, c = a + 2, e = a + 3; if (nz > 0) idx.push(a, c, b, b, c, e); else idx.push(a, b, c, b, e, c); }
      return base;
    };
    this._foot = face(d, 1); this._head = face(-d, -1);
    const base = v;
    for (let k = 0; k < 4; k++) { nor[(v) * 3] = 1; v++; }
    idx.push(base, base + 1, base + 2, base + 2, base + 1, base + 3);
    this._fore = base;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('normal', new THREE.BufferAttribute(nor, 3)); g.setAttribute('uv', new THREE.BufferAttribute(uv, 2)); g.setIndex(idx);
    const m = new THREE.Mesh(g, material); m.frustumCulled = false; return m;
  }

  _placeBlock(mesh, h, side) {
    mesh.visible = h > 1e-4;
    if (!mesh.visible) return;
    const g = mesh.geometry; const pos = g.attributes.position.array; const uv = g.attributes.uv.array;
    const W = PW - 0.008, M = BLOCK_COLS, d = (PH - 0.012) / 2, stripes = 90;
    const topAt = (i) => { const s = i / M; return Math.max(0.002, h - 0.0016 - GUTTER_DIP * (1 - smooth(0, 0.42, s))); };
    for (const [base, z] of [[this._foot, d], [this._head, -d]]) {
      for (let i = 0; i <= M; i++) {
        const x = 0.004 + (i / M) * W; const top = topAt(i);
        const a = (base + i * 2) * 3, b = a + 3;
        pos[a] = x; pos[a + 1] = 0; pos[a + 2] = z; pos[b] = x; pos[b + 1] = top; pos[b + 2] = z;
        uv[(base + i * 2) * 2 + 1] = 0; uv[(base + i * 2 + 1) * 2 + 1] = top * stripes;
      }
    }
    const f = this._fore; const top = topAt(M); const x = 0.004 + W;
    const corner = [[x, 0, -d, 0, 0], [x, 0, d, 4, 0], [x, top, -d, 0, top * stripes], [x, top, d, 4, top * stripes]];
    corner.forEach((c, k) => { pos[(f + k) * 3] = c[0]; pos[(f + k) * 3 + 1] = c[1]; pos[(f + k) * 3 + 2] = c[2]; uv[(f + k) * 2] = c[3]; uv[(f + k) * 2 + 1] = c[4]; });
    g.attributes.position.needsUpdate = true; g.attributes.uv.needsUpdate = true;
    mesh.scale.x = side; mesh.position.set(0, COVER_T, 0);
  }

  _deform(leaf) {
    const { p, peek, grabZ } = leaf;
    const { yr, yl } = this._restY(leaf.index);
    const eps = 0.0007 * (leaf.index + 1);
    const yRoot = lerp(yr, yl, p) + eps * (p < 0.5 ? 1 : 1);
    const nx = SX + 1, nz = SZ + 1;
    const pos = leaf.posAttr.array;
    const phiRoot = p * Math.PI;
    const lagAmp = 0.55 * Math.sin(2 * Math.PI * p) * (p > 0 && p < 1 ? 1 : 0);
    const flight = Math.sin(Math.PI * p);
    const ds = PW / SX;
    for (let iz = 0; iz < nz; iz++) {
      const zn = iz / SZ;                         // 0 = head (far), 1 = foot (near)
      const z = (zn - 0.5) * PH;
      const grab = 1 + 0.9 * (1 - Math.abs(zn - grabZ) * 1.4);
      let x = 0, y = yRoot;
      for (let ix = 0; ix < nx; ix++) {
        const s = ix / SX;
        const k = (iz * nx + ix) * 3;
        // gutter: resting leaves dip into the binding and rise toward the fore edge
        const dip = -GUTTER_DIP * (1 - smooth(0, 0.42, s)) * (1 - flight);
        let yy = y + dip;
        let xx = x;
        // hover/peek: lift the corner nearest the pointer
        if (peek > 0) yy += peek * 0.2 * smooth(0.5, 1, s) * smooth(0.15, 1, 1 - Math.abs(zn - grabZ) * 1.2) * (p === 0 ? 1 : 0.0);
        pos[k] = xx; pos[k + 1] = yy; pos[k + 2] = z;
        // advance along the sheet
        const phi = phiRoot - lagAmp * grab * Math.pow(s + 0.02, 1.25) * 0.9 - (peek > 0 && p === 0 ? -peek * 0.9 * s : 0);
        x += ds * Math.cos(phi); y += ds * Math.sin(phi);
      }
    }
    leaf.posAttr.needsUpdate = true;
    leaf.geo.computeVertexNormals();
    leaf.norAttr.array.set(leaf.geo.attributes.normal.array);
    leaf.dirty = false;
    // normals are shared by both meshes; geo.computeVertexNormals() wrote into the shared attribute already
    leaf.norAttr.needsUpdate = true;
  }

  _ribbon() {
    // A ribbon lying down the gutter of the right-hand page and hanging over the foot of the book.
    const g = this.ribbonGeo; const pos = g.attributes.position;
    const open = this.coverP;
    const { yr } = this._restY(0);
    const topY = Math.max(yr, COVER_T + this.bulk * 0.5);
    const rows = 13;
    for (let r = 0; r < rows; r++) {
      const t = r / (rows - 1);
      const z = lerp(-PH * 0.46, PH * 0.5 + 0.16, t);
      const over = Math.max(0, z - PH / 2);
      const y = over > 0 ? lerp(topY + 0.004, 0.0, smooth(0, 0.16, over)) + 0.002 : topY + 0.004;
      for (let c = 0; c < 2; c++) {
        const k = r * 2 + c;
        pos.setXYZ(k, 0.02 + c * 0.014, y, z);
      }
    }
    pos.needsUpdate = true; g.computeVertexNormals();
    this.ribbon.visible = open > 0.6 && this.n > 0;
  }

  // -------------------------------------------------------------------------------------------
  /** World-space height of the page surface for a face ('front' = right stack) near the outer area. */
  surfaceY(side) {
    const k = this.bulk / this.n;
    let r = 0, l = 0; for (const lf of this.leaves) { r += 1 - lf.p; l += lf.p; }
    return COVER_T + k * (side > 0 ? r : l) + 0.0007 * this.n + 0.001;
  }

  pageMeshes() { const out = []; for (const l of this.leaves) out.push(l.front, l.back); return out; }

  dispose() {
    this.group.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
  }
}
