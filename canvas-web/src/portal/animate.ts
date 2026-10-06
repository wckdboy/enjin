export function tween(durationMs: number, step: (t: number) => void): Promise<void> {
  return new Promise((resolve) => {
    const start = performance.now();
    const frame = (now: number) => {
      const t = Math.min(1, (now - start) / durationMs);
      step(easeInOut(t));
      if (t < 1) requestAnimationFrame(frame);
      else resolve();
    };
    requestAnimationFrame(frame);
  });
}

export const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export const nextPaint = () => new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));

/** Run a CSS transition on `el` and resolve when it finishes (or after a safety timeout). */
export function cssTransition(el: HTMLElement, styles: Partial<CSSStyleDeclaration>, ms: number): Promise<void> {
  return new Promise((resolve) => {
    el.style.transition = `transform ${ms}ms cubic-bezier(.2,.7,.2,1), opacity ${ms}ms ease`;
    Object.assign(el.style, styles);
    setTimeout(resolve, ms + 20);
  });
}

export function setStyleNow(el: HTMLElement, styles: Partial<CSSStyleDeclaration>): void {
  el.style.transition = "none";
  Object.assign(el.style, styles);
  void el.offsetWidth; // flush so the next transition starts from here
}
