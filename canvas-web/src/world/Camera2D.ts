import type { Rect } from "./spec";

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export interface View { s: number; tx: number; ty: number }

/**
 * The camera over the plane: screen = plane · s + t, in the coordinates of the
 * world you're in (the anchor). Diving into a world inside a door, or rising
 * out to the one around you, rebases those coordinates so they never run out:
 * the zoom is endless, the numbers stay small.
 */
export class Camera2D implements View {
  s = 0.5;
  tx = 0;
  ty = 0;
  w = 1;
  h = 1;
  insets = { top: 0, left: 0, bottom: 0, right: 0 };
  private flight: { from: Pose; to: Pose; t0: number; ms: number; done: () => void } | null = null;
  private vel = { x: 0, y: 0 };
  private lastMove = -1e9;
  private gliding = false;

  resize(w: number, h: number): void {
    this.w = w;
    this.h = h;
  }

  /** The part of the screen the native chrome leaves free. */
  free(): Rect {
    const i = this.insets;
    return { x: i.left, y: i.top, w: Math.max(1, this.w - i.left - i.right), h: Math.max(1, this.h - i.top - i.bottom) };
  }

  toScreen(x: number, y: number): [number, number] {
    return [x * this.s + this.tx, y * this.s + this.ty];
  }

  toPlane(sx: number, sy: number): [number, number] {
    return [(sx - this.tx) / this.s, (sy - this.ty) / this.s];
  }

  rectToScreen(r: Rect): Rect {
    return { x: r.x * this.s + this.tx, y: r.y * this.s + this.ty, w: r.w * this.s, h: r.h * this.s };
  }

  /** The view that shows `r` filling `fill` of the free area. */
  fit(r: Rect, fill = 0.92): View {
    const f = this.free();
    const s = Math.min((f.w * fill) / r.w, (f.h * fill) / r.h);
    return { s, tx: f.x + f.w / 2 - (r.x + r.w / 2) * s, ty: f.y + f.h / 2 - (r.y + r.h / 2) * s };
  }

  get flying(): boolean {
    return !!this.flight;
  }

  /** Moving on its own (a flight or a glide after a flick)? */
  moving(now: number): boolean {
    return !!this.flight || this.gliding || now - this.lastMove < 120;
  }

  stop(): void {
    this.flight = null;
    this.gliding = false;
  }

  panBy(dx: number, dy: number, now = performance.now()): void {
    this.tx += dx;
    this.ty += dy;
    this.gliding = false;
    // Remember the finger's speed for a glide after it lets go.
    const dt = Math.max(8, now - this.lastMove);
    this.vel = dt > 80 ? { x: 0, y: 0 } : { x: (dx / dt) * 16, y: (dy / dt) * 16 };
    this.lastMove = now;
  }

  zoomAt(sx: number, sy: number, factor: number): void {
    this.tx = sx - (sx - this.tx) * factor;
    this.ty = sy - (sy - this.ty) * factor;
    this.s *= factor;
    this.lastMove = performance.now();
  }

  /** Let go: keep gliding the way the finger was going. */
  release(): void {
    this.gliding = performance.now() - this.lastMove < 60 && Math.hypot(this.vel.x, this.vel.y) > 0.5;
  }

  set(v: View): void {
    this.flight = null;
    this.gliding = false;
    this.s = v.s;
    this.tx = v.tx;
    this.ty = v.ty;
  }

  /** Fly to a view: the centre moves while the zoom changes evenly (in log space), like a lens. */
  flyTo(v: View, ms = 800): Promise<void> {
    this.gliding = false;
    return new Promise((done) => {
      this.flight?.done();
      this.flight = { from: this.pose(this), to: this.pose(v), t0: performance.now(), ms, done };
    });
  }

  /** The world you're in changes to one placed at (ox, oy) at scale k in the current one's coordinates. */
  rebase(ox: number, oy: number, k: number): void {
    const re = (p: Pose): Pose => ({ cx: (p.cx - ox) / k, cy: (p.cy - oy) / k, ls: p.ls + Math.log(k) });
    this.tx += this.s * ox;
    this.ty += this.s * oy;
    this.s *= k;
    if (this.flight) { this.flight.from = re(this.flight.from); this.flight.to = re(this.flight.to); }
  }

  /** Advance flights and glides. True if the view changed. */
  update(now: number): boolean {
    if (this.flight) {
      const f = this.flight;
      const t = Math.min(1, (now - f.t0) / f.ms);
      const k = ease(t);
      const ls = f.from.ls + (f.to.ls - f.from.ls) * k;
      const cx = f.from.cx + (f.to.cx - f.from.cx) * k;
      const cy = f.from.cy + (f.to.cy - f.from.cy) * k;
      this.applyPose({ cx, cy, ls });
      if (t >= 1) { this.flight = null; f.done(); }
      return true;
    }
    if (this.gliding) {
      this.tx += this.vel.x;
      this.ty += this.vel.y;
      this.vel.x *= 0.93;
      this.vel.y *= 0.93;
      this.gliding = Math.hypot(this.vel.x, this.vel.y) > 0.05;
      return true;
    }
    return false;
  }

  /** A view as the plane point at the centre of the free area, and log zoom. */
  private pose(v: View): Pose {
    const f = this.free();
    return { cx: (f.x + f.w / 2 - v.tx) / v.s, cy: (f.y + f.h / 2 - v.ty) / v.s, ls: Math.log(v.s) };
  }

  private applyPose(p: Pose): void {
    const f = this.free();
    this.s = Math.exp(p.ls);
    this.tx = f.x + f.w / 2 - p.cx * this.s;
    this.ty = f.y + f.h / 2 - p.cy * this.s;
  }
}

type Pose = { cx: number; cy: number; ls: number };
