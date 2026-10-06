import type { Rect } from "../cards/layout";
import { onLangChange, t } from "../i18n";

export interface CardActionHandlers {
  open(cardId: string): void;
  dive(cardId: string): void;
}

/**
 * Small actions that sit on the selected card's top edge, so "what can I do
 * with this?" is answered right where the kid is looking (no floating sheet).
 */
export class CardActions {
  private host: HTMLDivElement;
  private open: HTMLButtonElement;
  private dive: HTMLButtonElement;
  private cardId: string | null = null;

  constructor(private handlers: CardActionHandlers) {
    this.host = document.createElement("div");
    this.host.dataset.enjin = "card-actions";
    Object.assign(this.host.style, {
      position: "absolute", left: "0", top: "0", zIndex: "3", display: "none", gap: "6px", padding: "5px",
      background: "#fffaf0", borderRadius: "16px", border: "2px solid #2a2a3c", boxShadow: "3px 4px 0 #2a2a3c",
      font: "700 16px ui-rounded, -apple-system, system-ui, sans-serif", transformOrigin: "50% 100%", transition: "opacity 120ms ease",
    });
    this.open = this.button("Open", "M4 4h7v2H6v12h12v-5h2v7H4V4zm10 0h6v6h-2V7.4l-7.3 7.3-1.4-1.4L16.6 6H14V4z", () => this.cardId && this.handlers.open(this.cardId));
    this.dive = this.button("Dive in", "M10 4a6 6 0 0 1 4.7 9.7l5 5-1.4 1.4-5-5A6 6 0 1 1 10 4zm0 2a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm-1 1.5h2V9h1.5v2H11v1.5H9V11H7.5V9H9V7.5z", () => this.cardId && this.handlers.dive(this.cardId));
    // "Dive in" is the main action: ember, like every "go" in ENJIN.
    Object.assign(this.dive.style, { background: "#e8590c", color: "#ffffff" });
    this.host.append(this.dive, this.open);
    onLangChange(() => this.relabel());
    this.relabel();
  }

  private relabel(): void {
    for (const [b, text] of [[this.open, t.actionOpen()], [this.dive, t.actionDive()]] as const) {
      b.setAttribute("aria-label", text);
      b.querySelector("span")!.textContent = text;
    }
  }

  private button(label: string, iconPath: string, onTap: () => void): HTMLButtonElement {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("aria-label", label);
    b.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="${iconPath}"/></svg><span>${label}</span>`;
    Object.assign(b.style, {
      display: "inline-flex", alignItems: "center", gap: "6px", minHeight: "40px", padding: "0 14px", border: "0", borderRadius: "11px",
      background: "transparent", color: "#2a2a3c", font: "inherit", cursor: "pointer", touchAction: "manipulation",
    });
    // Act on pointerup: Excalidraw would otherwise treat the press as a canvas gesture.
    b.addEventListener("pointerdown", (e) => e.stopPropagation());
    b.addEventListener("pointerup", (e) => {
      e.stopPropagation();
      onTap();
    });
    return b;
  }

  /** Show for `cardId` at its view-space rect, or hide (null). */
  update(cardId: string | null, viewRect: Rect | null, divable: boolean): void {
    if (!this.host.isConnected) (document.querySelector(".excalidraw") ?? document.body).appendChild(this.host);
    this.cardId = cardId;
    if (!cardId || !viewRect) {
      this.host.style.display = "none";
      return;
    }
    this.dive.style.display = divable ? "inline-flex" : "none";
    this.host.style.display = "flex";
    const w = this.host.offsetWidth;
    const h = this.host.offsetHeight;
    // Centered above the card; tucked inside it if there's no room on top.
    const x = Math.min(Math.max(8, viewRect.x + viewRect.width / 2 - w / 2), window.innerWidth - w - 8);
    const above = viewRect.y - h - 10;
    const y = above > 60 ? above : viewRect.y + 10;
    this.host.style.transform = `translate(${Math.round(x)}px, ${Math.round(y)}px)`;
  }
}
