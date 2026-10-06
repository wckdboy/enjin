import type { Rect } from "../cards/layout";
import { t } from "../i18n";

/**
 * Live models: small interactive simulations and animated dioramas the agent
 * writes as HTML. Each runs in its own sandboxed iframe laid over its card's
 * "live" slot, following pan and zoom.
 *
 * Isolation: `sandbox="allow-scripts"` without allow-same-origin gives the
 * frame an opaque origin (no access to this page, its storage or the native
 * bridge, which also refuses non-main frames), and a CSP that is in force before
 * any model-written markup blocks all network access.
 *
 * The models animate all the time but only take touches while their card is
 * selected, so panning the canvas over them still works.
 */
const CSP = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:";

/**
 * Model-written animation loops often throw on an odd frame (a zero-size first
 * frame, a negative radius) and, since they re-request at the end, stop dead.
 * Re-schedule a callback that threw, up to a limit, so one bad frame isn't fatal.
 */
const RESILIENT_RAF = `<script>(function(){var raf=window.requestAnimationFrame.bind(window),fails=0;
window.requestAnimationFrame=function(cb){return raf(function tick(t){try{cb(t);fails=0}catch(e){if(++fails<300)raf(tick);console.error(e)}})};})();</script>`;

export function liveDocument(html: string): string {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="${CSP}">${RESILIENT_RAF}
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#fff;color:#0b0b0c;
font:15px -apple-system,system-ui,sans-serif;-webkit-user-select:none;user-select:none;touch-action:none}</style>
</head><body>${html}</body></html>`;
}

export interface LiveSlot {
  cardId: string;
  html: string;
  /** Scene-space rect of the slot. */
  rect: Rect;
}

interface Frame {
  wrap: HTMLDivElement;
  iframe: HTMLIFrameElement;
  hint: HTMLDivElement;
  html: string;
}

export class LiveLayer {
  private host: HTMLDivElement;
  private frames = new Map<string, Frame>();

  constructor() {
    this.host = document.createElement("div");
    this.host.dataset.enjin = "live";
    Object.assign(this.host.style, { position: "absolute", inset: "0", zIndex: "2", pointerEvents: "none", overflow: "hidden" });
  }

  /**
   * Show exactly these slots at this viewport (Excalidraw maps scene to view as
   * (p + scroll) * zoom). `active` takes touches; `hidden` hides all (transitions).
   */
  sync(slots: LiveSlot[], vp: { scrollX: number; scrollY: number; zoom: number }, active: string | null, hidden: boolean): void {
    if (!this.host.isConnected) {
      const root = document.querySelector(".excalidraw");
      if (!root) return;
      root.appendChild(this.host);
    }
    this.host.style.display = hidden ? "none" : "block";
    const keep = new Set(slots.map((s) => s.cardId));
    for (const [id, f] of this.frames) {
      if (!keep.has(id)) {
        f.wrap.remove();
        this.frames.delete(id);
      }
    }
    for (const s of slots) {
      let f = this.frames.get(s.cardId);
      if (!f || f.html !== s.html) {
        f?.wrap.remove();
        f = this.make(s);
        this.frames.set(s.cardId, f);
      }
      const x = (s.rect.x + vp.scrollX) * vp.zoom;
      const y = (s.rect.y + vp.scrollY) * vp.zoom;
      Object.assign(f.wrap.style, {
        width: `${s.rect.width}px`,
        height: `${s.rect.height}px`,
        transform: `translate(${x}px, ${y}px) scale(${vp.zoom})`,
      });
      const on = active === s.cardId;
      f.iframe.style.pointerEvents = on ? "auto" : "none";
      f.wrap.style.boxShadow = on ? "0 0 0 2px #0b0b0c" : "0 0 0 1px #c9c9cd";
      f.hint.style.opacity = on ? "0" : "1";
    }
  }

  private make(s: LiveSlot): Frame {
    const wrap = document.createElement("div");
    Object.assign(wrap.style, {
      position: "absolute", left: "0", top: "0", transformOrigin: "0 0", borderRadius: "12px", overflow: "hidden", background: "#fff",
      // Sized before the frame loads: models read innerWidth/innerHeight on their first frame.
      width: `${s.rect.width}px`, height: `${s.rect.height}px`,
    });
    const iframe = document.createElement("iframe");
    iframe.setAttribute("sandbox", "allow-scripts");
    iframe.setAttribute("referrerpolicy", "no-referrer");
    iframe.setAttribute("title", "live model");
    iframe.dataset.cardId = s.cardId;
    iframe.srcdoc = liveDocument(s.html);
    Object.assign(iframe.style, { width: "100%", height: "100%", border: "0", display: "block" });
    const hint = document.createElement("div");
    hint.textContent = t.liveHint().toUpperCase();
    Object.assign(hint.style, {
      position: "absolute", right: "10px", top: "8px", font: "600 11px ui-monospace, Menlo, monospace", letterSpacing: "1px",
      color: "#6a6a70", background: "rgba(255,255,255,0.8)", padding: "3px 8px", borderRadius: "999px", pointerEvents: "none",
      transition: "opacity 160ms ease",
    });
    wrap.append(iframe, hint);
    this.host.appendChild(wrap);
    return { wrap, iframe, hint, html: s.html };
  }
}
