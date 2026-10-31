// Physical study tools. Each is a THREE.Group with a rest pose on the desk and a "use" pose over the book.
import * as THREE from 'three';
import { PW, PH } from './book3d.js';

const LENS_VERT = `
varying vec3 vWorld;
varying vec3 vOrigin;
void main(){ vec4 w = modelMatrix * vec4(position,1.0); vWorld = w.xyz; vOrigin = modelMatrix[3].xyz; gl_Position = projectionMatrix * viewMatrix * w; }`;

// The glass samples the page texture along the real view ray, magnified about the point under the lens centre.
const LENS_FRAG = `
precision highp float;
uniform sampler2D tPage;
uniform mat4 uWorldToBook;
uniform vec3 uCamBook;
uniform vec3 uCentre;      // book-local point on the page plane under the lens centre
uniform float uPlaneY;
uniform float uMag;
uniform float uSide;       // +1 right page (front face), -1 left page (back face)
uniform float uRtl;
uniform float uHas;
uniform float uPW;
uniform float uPH;
uniform float uTone;
uniform vec2 uRadial;      // radius in world units, edge softness
varying vec3 vWorld;
varying vec3 vOrigin;
void main(){
  vec3 fragB = (uWorldToBook * vec4(vWorld,1.0)).xyz;
  vec3 dir = fragB - uCamBook;
  float t = (uPlaneY - uCamBook.y) / dir.y;
  vec3 hit = uCamBook + dir * t;
  vec2 d = hit.xz - uCentre.xz;
  vec2 s = uCentre.xz + d / uMag;
  float x = s.x * uSide;                       // distance from the spine along the page
  float uvx = uSide > 0.0 ? x / uPW : 1.0 - x / uPW;
  uvx = uSide > 0.0 ? x / uPW : 1.0 - x / uPW;
  float texU = uRtl > 0.5 ? 1.0 - uvx : uvx;
  float texV = 1.0 - (s.y + uPH * 0.5) / uPH;
  vec3 col = vec3(0.93, 0.89, 0.8);
  if (uHas > 0.5 && texU >= 0.0 && texU <= 1.0 && texV >= 0.0 && texV <= 1.0) col = texture2D(tPage, vec2(texU, texV)).rgb;
  col *= uTone;
  // slight vignette and a cool rim like thick glass
  float r = length((vWorld - vOrigin).xz);
  gl_FragColor = vec4(col, 1.0);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}`;

export class Magnifier {
  constructor(maxAniso) {
    this.group = new THREE.Group();
    this.group.name = 'tool-lens';
    const R = 0.27;
    this.radius = R;
    const wood = new THREE.MeshStandardMaterial({ color: 0x5b3a22, roughness: 0.5 });
    const brass = new THREE.MeshStandardMaterial({ color: 0xcf9f3a, metalness: 1, roughness: 0.25 });
    // Handle: a turned wooden grip (lathe) pointing toward +z
    const pts = [];
    const prof = [[0.0, 0.0], [0.034, 0.0], [0.04, 0.05], [0.05, 0.14], [0.056, 0.26], [0.05, 0.34], [0.04, 0.4], [0.05, 0.43], [0.0, 0.44]];
    for (const [r, h] of prof) pts.push(new THREE.Vector2(r, h));
    const handleGeo = new THREE.LatheGeometry(pts, 28); handleGeo.rotateX(Math.PI / 2);
    const handle = new THREE.Mesh(handleGeo, wood); handle.position.set(0, 0, R + 0.1); handle.castShadow = true;
    const neckGeo = new THREE.CylinderGeometry(0.02, 0.026, 0.14, 16); neckGeo.rotateX(Math.PI / 2);
    const neck = new THREE.Mesh(neckGeo, brass); neck.position.set(0, 0, R + 0.04); neck.castShadow = true;
    const ferruleGeo = new THREE.CylinderGeometry(0.038, 0.034, 0.05, 20); ferruleGeo.rotateX(Math.PI / 2);
    const ferrule = new THREE.Mesh(ferruleGeo, brass); ferrule.position.set(0, 0, R + 0.1);
    // Rim and glass (horizontal in XZ)
    const rimGeo = new THREE.TorusGeometry(R, 0.02, 16, 64); rimGeo.rotateX(Math.PI / 2);
    const rim = new THREE.Mesh(rimGeo, brass); rim.castShadow = true;
    const rim2Geo = new THREE.TorusGeometry(R - 0.018, 0.007, 8, 64); rim2Geo.rotateX(Math.PI / 2);
    const rim2 = new THREE.Mesh(rim2Geo, new THREE.MeshStandardMaterial({ color: 0x8a6420, metalness: 1, roughness: 0.4 }));
    const gGeo = new THREE.CircleGeometry(R - 0.012, 64); gGeo.rotateX(-Math.PI / 2);
    this.uniforms = {
      tPage: { value: null }, uWorldToBook: { value: new THREE.Matrix4() }, uCamBook: { value: new THREE.Vector3() },
      uCentre: { value: new THREE.Vector3() }, uPlaneY: { value: 0 }, uMag: { value: 1.9 }, uSide: { value: 1 }, uRtl: { value: 0 },
      uHas: { value: 0 }, uPW: { value: PW }, uPH: { value: PH }, uTone: { value: 0.9 }, uRadial: { value: new THREE.Vector2(R, 0.02) },
    };
    this.glassMat = new THREE.ShaderMaterial({ uniforms: this.uniforms, vertexShader: LENS_VERT, fragmentShader: LENS_FRAG });
    this.restMat = new THREE.MeshPhysicalMaterial({ color: 0xcfe6ea, transparent: true, opacity: 0.35, roughness: 0.05, metalness: 0, clearcoat: 1 });
    this.glass = new THREE.Mesh(gGeo, this.restMat);
    // A faint reflective film over the magnified image, so the lens reads as glass
    const sheenGeo = new THREE.CircleGeometry(R - 0.012, 48); sheenGeo.rotateX(-Math.PI / 2);
    this.sheen = new THREE.Mesh(sheenGeo, new THREE.MeshPhysicalMaterial({ color: 0xffffff, transparent: true, opacity: 0.07, roughness: 0.02, metalness: 0, clearcoat: 1, depthWrite: false }));
    this.sheen.position.y = 0.002;
    this.group.add(handle, neck, ferrule, rim, rim2, this.glass, this.sheen);
    this.group.traverse((o) => { o.userData.tool = 'lens'; });
    this.restPos = new THREE.Vector3(-0.58, 0.05, -1.55);
    this.restRot = new THREE.Euler(0, 0.55, 0);
    this.group.position.copy(this.restPos); this.group.rotation.copy(this.restRot);
    this.active = false;
    this.rim = rim;
  }
  /** Switch the glass between plain (resting) and the magnifying shader. */
  setMagnifying(on, has) { this.glass.material = on ? this.glassMat : this.restMat; this.uniforms.uHas.value = on && has ? 1 : 0; this.sheen.visible = true; }
}

export class Bookmark {
  constructor() {
    this.group = new THREE.Group(); this.group.name = 'tool-bookmark';
    const card = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.006, 0.48), new THREE.MeshStandardMaterial({ color: 0xd97757, roughness: 0.7 }));
    card.castShadow = true; card.receiveShadow = true; card.position.y = 0.003;
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.0015, 0.012), new THREE.MeshStandardMaterial({ color: 0xe4b44f, metalness: 0.9, roughness: 0.3 }));
    stripe.position.set(0, 0.0068, -0.15);
    const stripe2 = stripe.clone(); stripe2.position.z = -0.12;
    const hole = new THREE.Mesh(new THREE.CylinderGeometry(0.016, 0.016, 0.0075, 16), new THREE.MeshStandardMaterial({ color: 0x1b1a18 })); hole.position.set(0, 0.0035, 0.19);
    const cord = new THREE.Mesh(new THREE.CylinderGeometry(0.004, 0.004, 0.2, 8), new THREE.MeshStandardMaterial({ color: 0xe4b44f, roughness: 0.8 }));
    cord.rotation.x = Math.PI / 2; cord.position.set(0, 0.004, 0.31);
    const tassel = new THREE.Mesh(new THREE.ConeGeometry(0.022, 0.1, 12), new THREE.MeshStandardMaterial({ color: 0xe4b44f, roughness: 0.8 })); tassel.rotation.x = -Math.PI / 2; tassel.position.set(0, 0.004, 0.46);
    this.group.add(card, stripe, stripe2, hole, cord, tassel);
    this.group.traverse((o) => { o.userData.tool = 'bookmark'; });
    this.restPos = new THREE.Vector3(0.12, 0.016, -1.5);
    this.restRot = new THREE.Euler(0, -0.35, 0);
    this.group.position.copy(this.restPos); this.group.rotation.copy(this.restRot);
  }
}

export class Ruler {
  constructor() {
    this.group = new THREE.Group(); this.group.name = 'tool-ruler';
    const L = 1.12, Wd = 0.15;
    const mat = new THREE.MeshPhysicalMaterial({ color: 0xf2b68f, transparent: true, opacity: 0.55, roughness: 0.15, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.1, side: THREE.DoubleSide, depthWrite: false });
    const body = new THREE.Mesh(new THREE.BoxGeometry(L, 0.012, Wd), mat); body.position.y = 0.006; body.castShadow = false;
    const edge = new THREE.Mesh(new THREE.BoxGeometry(L, 0.016, 0.01), new THREE.MeshStandardMaterial({ color: 0xd97757, roughness: 0.4 })); edge.position.set(0, 0.008, Wd / 2);
    this.group.add(body, edge);
    const tick = new THREE.MeshStandardMaterial({ color: 0x3b2418, roughness: 0.8 });
    for (let i = 0; i <= 28; i++) {
      const long = i % 5 === 0;
      const t = new THREE.Mesh(new THREE.BoxGeometry(0.003, 0.0016, long ? 0.04 : 0.022), tick);
      t.position.set(-L / 2 + 0.03 + (i * (L - 0.06)) / 28, 0.0128, Wd / 2 - (long ? 0.03 : 0.02)); this.group.add(t);
    }
    this.group.traverse((o) => { o.userData.tool = 'ruler'; });
    this.restPos = new THREE.Vector3(0.55, 0.016, -1.2);
    this.restRot = new THREE.Euler(0, 0.12, 0);
    this.group.position.copy(this.restPos); this.group.rotation.copy(this.restRot);
    this.width = Wd; this.length = L;
  }
}
