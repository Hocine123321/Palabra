// A tiny tween engine driven by the render loop.
export const ease = {
  linear: (t) => t,
  inOut: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  out: (t) => 1 - Math.pow(1 - t, 3),
  inOutSine: (t) => -(Math.cos(Math.PI * t) - 1) / 2,
  outBack: (t) => { const c1 = 1.4, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); },
};

export class Tweens {
  constructor() { this.list = []; this.scale = 1; }
  /** @param {{duration:number, delay?:number, ease?:Function, onUpdate:(t:number)=>void, onDone?:()=>void}} spec */
  add(spec) {
    const tw = { t: -(spec.delay || 0), dur: Math.max(0.0001, spec.duration * this.scale), delay: (spec.delay || 0) * this.scale,
      ease: spec.ease || ease.inOut, onUpdate: spec.onUpdate, onDone: spec.onDone, dead: false };
    tw.t = -tw.delay;
    this.list.push(tw);
    return tw;
  }
  get active() { return this.list.length > 0; }
  update(dt) {
    for (const tw of this.list) {
      tw.t += dt;
      if (tw.t < 0) continue;
      const p = Math.min(1, tw.t / tw.dur);
      tw.onUpdate(tw.ease(p));
      if (p >= 1) { tw.dead = true; if (tw.onDone) tw.onDone(); }
    }
    if (this.list.some((t) => t.dead)) this.list = this.list.filter((t) => !t.dead);
  }
  cancel(tw) { if (tw) tw.dead = true; }
}
