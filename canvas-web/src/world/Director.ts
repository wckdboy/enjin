import * as THREE from "three";

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/**
 * The camera: an orbit around a focus point that you drag and pinch, plus
 * directed moves (fly to a thing, dive through a door, pull back out of one).
 * Native chrome (tool rail, dock) is kept clear with a view offset.
 */
export class Director {
  readonly camera = new THREE.PerspectiveCamera(42, 1, 0.1, 200);
  az = 0;
  el = 0.2;
  dist = 15;
  focus = new THREE.Vector3(0, 0.6, 0);
  minDist = 3;
  maxDist = 26;
  private flight: { from: State; to: State; t0: number; ms: number; done: () => void } | null = null;
  private pointers = new Map<number, { x: number; y: number }>();
  private pinch0 = 0;
  private dist0 = 0;
  private moved = 0;
  private lastInput = -1e9;
  private insets = { top: 0, left: 0, bottom: 0, right: 0 };
  private size = { w: 1, h: 1 };
  idleSpin = true;
  onTap: ((x: number, y: number, target: EventTarget | null) => void) | null = null;
  onPullOut: (() => void) | null = null;

  constructor(private host: HTMLElement) {
    host.addEventListener("pointerdown", (e) => {
      if ((e.target as HTMLElement).closest?.(".panel.on iframe, .hud")) return;
      this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      this.moved = 0;
      this.lastInput = performance.now();
      if (this.pointers.size === 2) {
        const [a, b] = [...this.pointers.values()];
        this.pinch0 = Math.hypot(a!.x - b!.x, a!.y - b!.y);
        this.dist0 = this.dist;
      }
    });
    host.addEventListener("pointermove", (e) => {
      const prev = this.pointers.get(e.pointerId);
      if (!prev || this.flight) return;
      this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      this.moved += Math.abs(e.clientX - prev.x) + Math.abs(e.clientY - prev.y);
      this.lastInput = performance.now();
      if (this.pointers.size === 1) {
        this.az -= (e.clientX - prev.x) * 0.006;
        this.el = Math.max(-0.15, Math.min(1.25, this.el + (e.clientY - prev.y) * 0.004));
      } else if (this.pointers.size === 2 && this.pinch0 > 0) {
        const [a, b] = [...this.pointers.values()];
        const d = Math.hypot(a!.x - b!.x, a!.y - b!.y);
        this.dist = Math.max(this.minDist, Math.min(this.maxDist * 1.25, (this.dist0 * this.pinch0) / Math.max(1, d)));
      }
    });
    const up = (e: PointerEvent) => {
      const was = this.pointers.size;
      this.pointers.delete(e.pointerId);
      if (was === 1 && this.moved < 8) this.onTap?.(e.clientX, e.clientY, e.target);
      if (was === 2 && this.dist > this.maxDist * 1.12) this.onPullOut?.();
      if (this.dist > this.maxDist) this.dist = this.maxDist;
    };
    host.addEventListener("pointerup", up);
    host.addEventListener("pointercancel", up);
    host.addEventListener("wheel", (e) => {
      e.preventDefault();
      this.dist = Math.max(this.minDist, Math.min(this.maxDist, this.dist * (1 + e.deltaY * 0.001)));
      this.lastInput = performance.now();
    }, { passive: false });
  }

  setInsets(i: { top: number; left: number; bottom: number; right: number }): void {
    this.insets = i;
    this.resize(this.size.w, this.size.h);
  }

  resize(w: number, h: number): void {
    this.size = { w, h };
    this.camera.aspect = w / h;
    // Portrait: widen the view so the room still fits side to side (at least ~50° across).
    const across = 2 * Math.atan(Math.tan((25 * Math.PI) / 180) / this.camera.aspect);
    this.camera.fov = Math.max(42, (across * 180) / Math.PI);
    // Centre the view in the space the chrome leaves free.
    const dx = (this.insets.left - this.insets.right) / 2;
    const dy = (this.insets.top - this.insets.bottom) / 2;
    this.camera.setViewOffset(w, h, -dx, -dy, w, h);
    this.camera.updateProjectionMatrix();
  }

  /** Has the explorer touched it recently (or is the camera moving)? */
  busy(now: number): boolean {
    return !!this.flight || now - this.lastInput < 600 || this.pointers.size > 0;
  }

  /** Left alone, the room turns slowly for a while, then rests (to save the battery). */
  drifting(now: number): boolean {
    const idle = now - this.lastInput;
    return this.idleSpin && idle > 4000 && idle < 90000;
  }

  update(now: number): void {
    if (this.flight) {
      const f = this.flight;
      const t = Math.min(1, (now - f.t0) / f.ms);
      const k = ease(t);
      this.az = f.from.az + (f.to.az - f.from.az) * k;
      this.el = f.from.el + (f.to.el - f.from.el) * k;
      this.dist = f.from.dist + (f.to.dist - f.from.dist) * k;
      this.focus.lerpVectors(f.from.focus, f.to.focus, k);
      if (t >= 1) { this.flight = null; f.done(); }
    } else if (this.drifting(now)) {
      this.az += 0.0009;
    }
    const c = this.camera;
    c.position.set(
      this.focus.x + this.dist * Math.cos(this.el) * Math.sin(this.az),
      this.focus.y + this.dist * Math.sin(this.el),
      this.focus.z + this.dist * Math.cos(this.el) * Math.cos(this.az),
    );
    c.lookAt(this.focus);
  }

  /** Fly so that `point` is in front of the camera at `dist`, looking from the centre outwards toward it. */
  flyTo(point: THREE.Vector3, dist: number, ms = 900, fromCentre = false): Promise<void> {
    // Look at the point from outside the ring (or from the centre, for panels on the far wall).
    const dir = new THREE.Vector3(point.x, 0, point.z).normalize();
    const az = Math.atan2(dir.x, dir.z) + (fromCentre ? Math.PI : 0);
    let daz = az - this.az;
    daz = Math.atan2(Math.sin(daz), Math.cos(daz));
    return this.fly({ az: this.az + daz, el: 0.12, dist, focus: point.clone() }, ms);
  }

  /** Back to the front view of the whole room (the shortest way round). */
  overview(ms = 900): Promise<void> {
    const az = this.az - Math.atan2(Math.sin(this.az), Math.cos(this.az));
    return this.fly({ az, el: 0.2, dist: 15, focus: new THREE.Vector3(0, 0.6, 0) }, ms);
  }

  fly(to: State, ms: number): Promise<void> {
    return new Promise((done) => {
      this.flight = { from: { az: this.az, el: this.el, dist: this.dist, focus: this.focus.clone() }, to, t0: performance.now(), ms, done };
    });
  }

  /** Jump without animating (after a world swap). */
  set(s: Partial<State>): void {
    if (s.az !== undefined) this.az = s.az;
    if (s.el !== undefined) this.el = s.el;
    if (s.dist !== undefined) this.dist = s.dist;
    if (s.focus) this.focus.copy(s.focus);
  }
}

type State = { az: number; el: number; dist: number; focus: THREE.Vector3 };
