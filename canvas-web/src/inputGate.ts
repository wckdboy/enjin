// Blocks finger input to Excalidraw while a pencil stroke is active or a portal
// transition is running. Installed in the window capture phase, so it runs
// before Excalidraw's own document/canvas listeners.
//
// We never block pointerup/pointercancel/touchend: Excalidraw tracks active
// pointers for pinch, and swallowing the "up" would leave it with ghost touches.

const BLOCKED = ["pointerdown", "pointermove", "touchstart", "touchmove", "gesturestart", "gesturechange", "wheel"] as const;
const PEN = ["pointerdown", "pointermove", "pointerup", "pointercancel", "touchstart", "touchmove", "touchend", "touchcancel"] as const;

/** Pencil belongs to the native PencilKit layer; the canvas must never see it. */
function isPencil(e: Event): boolean {
  if (e instanceof PointerEvent) return e.pointerType === "pen";
  if (typeof TouchEvent !== "undefined" && e instanceof TouchEvent) {
    const touches = Array.from(e.changedTouches) as (Touch & { touchType?: string })[];
    return touches.length > 0 && touches.every((t) => t.touchType === "stylus");
  }
  return false;
}

export class InputGate {
  private reasons = new Set<string>();
  private activeTouches = 0;
  /** Set when a gesture was in progress at block time; we stay blocked until all fingers lift. */
  private drainUntilLift = false;

  constructor() {
    for (const type of PEN) window.addEventListener(type, this.onPen, { capture: true, passive: false });
    for (const type of BLOCKED) window.addEventListener(type, this.onBlocked, { capture: true, passive: false });
    // Fingers only: a resting pencil must not keep the gate draining.
    window.addEventListener("touchstart", this.countTouches, { capture: true });
    window.addEventListener("touchend", this.countTouches, { capture: true });
    window.addEventListener("touchcancel", this.countTouches, { capture: true });
  }

  block(reason: string): void {
    this.reasons.add(reason);
    if (this.activeTouches > 0) this.drainUntilLift = true;
  }

  unblock(reason: string): void {
    this.reasons.delete(reason);
  }

  get blocked(): boolean {
    return this.reasons.size > 0 || this.drainUntilLift;
  }

  private countTouches = (e: TouchEvent) => {
    this.activeTouches = (Array.from(e.touches) as (Touch & { touchType?: string })[]).filter((t) => t.touchType !== "stylus").length;
    if (this.activeTouches === 0) this.drainUntilLift = false;
  };

  private onPen = (e: Event) => {
    if (!isPencil(e)) return;
    e.stopImmediatePropagation();
    if (e.cancelable) e.preventDefault();
  };

  private onBlocked = (e: Event) => {
    if (!this.blocked || isPencil(e)) return;
    e.stopImmediatePropagation();
    if (e.cancelable) e.preventDefault();
  };
}
