import type { Rect } from "../cards/layout";

/**
 * A canvas drawn above Excalidraw during dive/exit, showing a pre-rendered
 * portal inside a card's window. Positioned with a transform each frame, so
 * it tracks the camera without re-rendering.
 */
export class PreviewOverlay {
  private el: HTMLCanvasElement | null = null;
  private host: HTMLDivElement;

  constructor() {
    this.host = document.createElement("div");
    // Above Excalidraw's canvases (z 1-2), below its toolbar/UI layer (z 4),
    // so the UI never blinks out while a portal fills the screen.
    Object.assign(this.host.style, { position: "absolute", inset: "0", pointerEvents: "none", zIndex: "3", overflow: "hidden" });
    this.host.dataset.enjin = "preview-overlay";
  }

  private attach(): void {
    if (this.host.isConnected) return;
    (document.querySelector(".excalidraw") ?? document.body).appendChild(this.host);
  }

  /** Show `canvas` (rendered at full-viewport size) scaled into `rect` (view coords). */
  show(canvas: HTMLCanvasElement, rect: Rect, opacity: number): void {
    this.attach();
    const w = this.host.clientWidth || window.innerWidth;
    const h = this.host.clientHeight || window.innerHeight;
    if (this.el !== canvas) {
      this.el?.remove();
      this.el = canvas;
      Object.assign(canvas.style, { position: "absolute", left: "0", top: "0", width: `${w}px`, height: `${h}px`, transformOrigin: "0 0", willChange: "transform, opacity" });
      this.host.appendChild(canvas);
    }
    const s = rect.width / w;
    canvas.style.transition = "none";
    canvas.style.transform = `translate(${rect.x}px, ${rect.y}px) scale(${s})`;
    canvas.style.opacity = String(opacity);
  }

  async fadeOut(ms: number): Promise<void> {
    const el = this.el;
    if (!el) return;
    el.style.transition = `opacity ${ms}ms linear`;
    el.style.opacity = "0";
    await new Promise((r) => setTimeout(r, ms + 10));
    if (this.el === el) this.hide();
  }

  hide(): void {
    this.el?.remove();
    this.el = null;
  }

  get visible(): boolean {
    return this.el !== null;
  }
}
