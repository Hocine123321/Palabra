// The room: a real desk (rounded slab with a wood grain), a leather-edged felt mat, paper cut-outs in the
// Palabra palette, a lamp, an inkwell and a pencil. All meshes; lighting comes from the scene's lights.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';

function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function rng(seed) { let s = seed; return () => { s = (s * 16807) % 2147483647; return s / 2147483647; }; }

function woodTextures(aniso) {
  const W = 1024, H = 1024;
  const c = canvas(W, H), g = c.getContext('2d');
  const b = canvas(W, H), bg = b.getContext('2d');
  const r = rng(42);
  const planks = 4;
  for (let p = 0; p < planks; p++) {
    const x0 = (p * W) / planks;
    const tone = 0.9 + r() * 0.2;
    g.fillStyle = `rgb(${Math.round(196 * tone)},${Math.round(150 * tone)},${Math.round(104 * tone)})`;
    g.fillRect(x0, 0, W / planks, H);
    for (let i = 0; i < 90; i++) {
      const x = x0 + r() * (W / planks); const a = 0.03 + r() * 0.08;
      g.strokeStyle = r() > 0.5 ? `rgba(90,50,20,${a})` : `rgba(255,225,180,${a * 0.7})`;
      g.lineWidth = 1 + r() * 2.2; g.beginPath(); g.moveTo(x, 0);
      let yy = 0; let xx = x;
      while (yy < H) { yy += 40; xx += (r() - 0.5) * 5; g.lineTo(xx, yy); }
      g.stroke();
    }
    g.fillStyle = 'rgba(40,20,5,0.55)'; g.fillRect(x0, 0, 3, H);
  }
  bg.fillStyle = '#808080'; bg.fillRect(0, 0, W, H);
  for (let i = 0; i < 700; i++) { bg.strokeStyle = r() > 0.5 ? 'rgba(0,0,0,0.25)' : 'rgba(255,255,255,0.25)'; bg.lineWidth = 1; const x = r() * W; bg.beginPath(); bg.moveTo(x, 0); bg.lineTo(x + (r() - 0.5) * 10, H); bg.stroke(); }
  for (let p = 0; p < planks; p++) { bg.fillStyle = 'rgba(0,0,0,0.9)'; bg.fillRect((p * W) / planks, 0, 4, H); }
  const map = new THREE.CanvasTexture(c); map.colorSpace = THREE.SRGBColorSpace;
  const bump = new THREE.CanvasTexture(b);
  for (const t of [map, bump]) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(3, 3.4); t.anisotropy = aniso; }
  return { map, bump };
}

function feltTexture() {
  const c = canvas(256, 256), g = c.getContext('2d'); const r = rng(5);
  g.fillStyle = '#ffffff'; g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 6000; i++) { g.fillStyle = `rgba(0,0,0,${r() * 0.08})`; g.fillRect(r() * 256, r() * 256, 1.5, 1.5); }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(6, 6); return t;
}

export class Room {
  constructor(maxAniso) {
    this.group = new THREE.Group();
    this.props = new THREE.Group();   // things that vanish in Focus Mode
    const wood = woodTextures(maxAniso);
    this.woodMat = new THREE.MeshStandardMaterial({ map: wood.map, bumpMap: wood.bump, bumpScale: 1.4, roughness: 0.62 });
    const top = new THREE.Mesh(new RoundedBoxGeometry(18, 0.3, 20, 4, 0.06), this.woodMat);
    top.position.set(0, -0.15, -6.1); top.receiveShadow = true; top.castShadow = true;
    this.group.add(top);

    // Felt mat with a stitched leather edge
    this.matMat = new THREE.MeshStandardMaterial({ map: feltTexture(), color: 0xa3b18a, roughness: 1 });
    const mat = new THREE.Mesh(new RoundedBoxGeometry(3.3, 0.016, 4.3, 3, 0.006), this.matMat);
    mat.position.set(0, 0.008, -0.1); mat.receiveShadow = true;
    this.group.add(mat);
    const edge = new THREE.Mesh(new RoundedBoxGeometry(3.34, 0.012, 4.34, 3, 0.005), new THREE.MeshStandardMaterial({ color: 0x4a3426, roughness: 0.55 }));
    edge.position.set(0, 0.004, -0.1); edge.receiveShadow = true; this.group.add(edge);
    this.mat = mat;

    this._cutouts();
    this._lamp();
    this._smallProps();
    this.group.add(this.props);
  }

  /** Paper cut-outs in Palabra's palette: thin extruded sheets lying on the desk. */
  _cutouts() {
    const make = (shape, color, x, z, rot, thick = 0.012) => {
      const geo = new THREE.ExtrudeGeometry(shape, { depth: thick, bevelEnabled: true, bevelSize: 0.004, bevelThickness: 0.003, bevelSegments: 2, curveSegments: 24 });
      geo.rotateX(-Math.PI / 2);
      const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color, roughness: 0.9 }));
      m.position.set(x, 0.016, z); m.rotation.y = rot; m.castShadow = true; m.receiveShadow = true; this.props.add(m); return m;
    };
    const circle = new THREE.Shape(); circle.absarc(0, 0, 0.42, 0, Math.PI * 2);
    const quarter = new THREE.Shape(); quarter.moveTo(0, 0); quarter.lineTo(0.7, 0); quarter.absarc(0, 0, 0.7, 0, Math.PI / 2, false); quarter.lineTo(0, 0);
    const rr = new THREE.Shape(); const s = 0.32, r = 0.1; rr.moveTo(-s + r, -s); rr.lineTo(s - r, -s); rr.quadraticCurveTo(s, -s, s, -s + r); rr.lineTo(s, s - r); rr.quadraticCurveTo(s, s, s - r, s); rr.lineTo(-s + r, s); rr.quadraticCurveTo(-s, s, -s, s - r); rr.lineTo(-s, -s + r); rr.quadraticCurveTo(-s, -s, -s + r, -s);
    this.cutouts = [
      make(circle, 0xd97757, 1.25, -2.05, 0),
      make(quarter, 0xa3b18a, -1.45, 1.85, 0.4),
      make(rr, 0x9dbad5, -1.35, -2.25, 0.5),
      make(circle, 0xebb491, 1.2, 2.25, 0),
    ];
    this.cutouts[3].scale.setScalar(0.55);
  }

  _lamp() {
    const lamp = new THREE.Group();
    const metal = new THREE.MeshStandardMaterial({ color: 0x2b2a28, metalness: 0.7, roughness: 0.38 });
    const brass = new THREE.MeshStandardMaterial({ color: 0xc9992f, metalness: 0.95, roughness: 0.28 });
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.4, 0.07, 40), metal); base.position.y = 0.035; base.castShadow = true;
    const stem = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1.25, 16), brass); stem.position.y = 0.66; stem.castShadow = true;
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.026, 1.1, 16), brass);
    arm.position.set(0.42, 1.25, 0); arm.rotation.z = -1.15; arm.castShadow = true;
    const joint = new THREE.Mesh(new THREE.SphereGeometry(0.06, 16, 12), brass); joint.position.set(0, 1.28, 0);
    const shadeGeo = new THREE.CylinderGeometry(0.1, 0.42, 0.42, 40, 1, true);
    this.shadeMat = new THREE.MeshStandardMaterial({ color: 0x1f5f4a, metalness: 0.2, roughness: 0.4, side: THREE.DoubleSide });
    const shade = new THREE.Mesh(shadeGeo, this.shadeMat); shade.position.set(0.98, 1.58, 0); shade.rotation.z = 0.0; shade.castShadow = true;
    this.bulbMat = new THREE.MeshStandardMaterial({ color: 0xfff1c8, emissive: 0xffd48a, emissiveIntensity: 0, roughness: 0.4 });
    const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.1, 20, 16), this.bulbMat); bulb.position.set(0.98, 1.55, 0);
    lamp.add(base, stem, arm, joint, shade, bulb);
    lamp.position.set(-4.6, 0.016, -2.6); lamp.rotation.y = 0.5;
    lamp.userData.bulbWorld = new THREE.Vector3();
    this.lamp = lamp; this.props.add(lamp);
  }

  _smallProps() {
    // Inkwell
    const ink = new THREE.Group();
    const glass = new THREE.MeshPhysicalMaterial({ color: 0x1b2a38, roughness: 0.05, metalness: 0, transmission: 0.0, clearcoat: 1, clearcoatRoughness: 0.05 });
    const body = new THREE.Mesh(new RoundedBoxGeometry(0.22, 0.2, 0.22, 3, 0.04), glass); body.position.y = 0.1; body.castShadow = true;
    const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.06, 0.05, 20), new THREE.MeshStandardMaterial({ color: 0xc9992f, metalness: 0.9, roughness: 0.3 })); cap.position.y = 0.225;
    ink.add(body, cap); ink.position.set(1.4, 0.016, -1.65); ink.rotation.y = 0.4; this.props.add(ink);
    // Pencil
    const pencil = new THREE.Group();
    const wood = new THREE.Mesh(new THREE.CylinderGeometry(0.016, 0.016, 0.62, 6), new THREE.MeshStandardMaterial({ color: 0xe9b43c, roughness: 0.55 }));
    wood.rotation.z = Math.PI / 2; wood.castShadow = true;
    const tip = new THREE.Mesh(new THREE.ConeGeometry(0.016, 0.07, 6), new THREE.MeshStandardMaterial({ color: 0xe8cfa2, roughness: 0.8 })); tip.rotation.z = Math.PI / 2; tip.position.x = 0.345;
    const lead = new THREE.Mesh(new THREE.ConeGeometry(0.006, 0.022, 6), new THREE.MeshStandardMaterial({ color: 0x222222, roughness: 0.5 })); lead.rotation.z = Math.PI / 2; lead.position.x = 0.389;
    const end = new THREE.Mesh(new THREE.CylinderGeometry(0.0175, 0.0175, 0.05, 6), new THREE.MeshStandardMaterial({ color: 0xd97757, roughness: 0.6 })); end.rotation.z = Math.PI / 2; end.position.x = -0.335;
    pencil.add(wood, tip, lead, end); pencil.position.set(0.9, 0.034, -1.95); pencil.rotation.y = -0.35; this.props.add(pencil);
  }

  setAppearance(dark) {
    this.woodMat.color.set(dark ? 0x8f6a4a : 0xffffff);
    this.matMat.color.set(dark ? 0x4d5642 : 0xa3b18a);
    this.bulbMat.emissiveIntensity = dark ? 2.5 : 0.0;
  }
}
