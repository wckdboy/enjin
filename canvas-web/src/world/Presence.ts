import type { Params, NativeToWeb } from "../bridge/schema";
import { t } from "../i18n";

export type EnjinState = Params<NativeToWeb, "enjin.state">;

/**
 * Enjin, on the canvas: a small glass orb with an ink ring that turns while it
 * works. It goes where the work is (the card it's writing, the thing you're
 * looking at), talks in a bubble right there, asks its questions there, and
 * you tap it to talk back: no looking down at a search bar.
 */
export class Presence {
  readonly el = document.createElement("div");
  private orb = document.createElement("button");
  private bubble = document.createElement("div");
  private words = document.createElement("div");
  private chips = document.createElement("div");
  private row = document.createElement("form");
  private input = document.createElement("input");
  private stop = document.createElement("button");
  private undo = document.createElement("button");
  private state: EnjinState = { status: "idle", text: "", steps: [], canUndo: false };
  private pos = { x: -100, y: -100 };
  private target = { x: -100, y: -100 };
  private placed = false;
  /** Talking (bubble open) until this time, unless something keeps it open. */
  private openUntil = 0;
  private composing = false;
  private lastText = "";

  onAsk: (text: string) => void = () => {};
  onAnswer: (choice: string) => void = () => {};
  onStep: (id: string) => void = () => {};
  onControl: (action: "stop" | "undo" | "dismissQuestion" | "dismissError") => void = () => {};
  onTyping: (typing: boolean) => void = () => {};

  constructor(host: HTMLElement) {
    this.el.className = "enjin";
    this.orb.className = "enjin-orb";
    this.orb.setAttribute("aria-label", "Enjin");
    this.orb.innerHTML = `<svg viewBox="-24 -24 48 48" aria-hidden="true"><ellipse class="ring" rx="13" ry="5.2" fill="none" stroke-width="2.6"/><circle class="core" r="2.6"/></svg>`;
    this.bubble.className = "enjin-bubble off";
    this.words.className = "words";
    this.chips.className = "chips";
    this.row.className = "talk";
    this.input.placeholder = t.askEnjin();
    this.input.enterKeyHint = "send";
    this.stop.type = "button";
    this.stop.className = "stop";
    this.undo.type = "button";
    this.undo.className = "undo";
    this.row.append(this.input);
    this.bubble.append(this.words, this.chips, this.row, this.stop, this.undo);
    this.el.append(this.bubble, this.orb);
    host.appendChild(this.el);

    this.orb.addEventListener("click", () => {
      // Tap Enjin to talk to it (or to put the conversation away).
      if (this.isOpen() && this.composing) this.close();
      else this.compose();
    });
    this.row.addEventListener("submit", (e) => {
      e.preventDefault();
      const text = this.input.value.trim();
      if (!text) return;
      this.input.value = "";
      this.input.blur();
      this.composing = false;
      this.onAsk(text);
    });
    this.input.addEventListener("focus", () => this.onTyping(true));
    this.input.addEventListener("blur", () => this.onTyping(false));
    this.stop.addEventListener("click", () => this.onControl("stop"));
    this.undo.addEventListener("click", () => this.onControl("undo"));
    this.render();
  }

  get status(): EnjinState["status"] {
    return this.state.status;
  }

  set(s: EnjinState): void {
    const spoke = s.text !== this.lastText && s.text.length > 0;
    this.state = s;
    this.lastText = s.text;
    // New words, a question or an offer: open and stay a while.
    if (spoke || s.question || s.status === "failed") this.openUntil = performance.now() + 14000;
    this.render();
  }

  /** Where Enjin should be (screen px): the work, or a resting spot. */
  goTo(x: number, y: number): void {
    this.target = { x, y };
    if (!this.placed) { this.pos = { ...this.target }; this.placed = true; }
  }

  /** Move toward the target; true while still moving. */
  update(dt: number): boolean {
    const k = 1 - Math.exp(-dt * 5.5);
    const dx = this.target.x - this.pos.x, dy = this.target.y - this.pos.y;
    this.pos.x += dx * k;
    this.pos.y += dy * k;
    this.el.style.transform = `translate(${this.pos.x}px, ${this.pos.y}px)`;
    // The bubble opens toward the middle of the screen.
    const left = this.pos.x > innerWidth / 2;
    const up = this.pos.y > innerHeight * 0.55;
    this.bubble.classList.toggle("left", left);
    this.bubble.classList.toggle("up", up);
    const wasOpen = this.bubble.classList.contains("off") === false;
    if (wasOpen !== this.isOpen()) this.render();
    return Math.abs(dx) + Math.abs(dy) > 0.5;
  }

  /** Open the bubble to type to Enjin. */
  compose(): void {
    this.composing = true;
    this.openUntil = performance.now() + 60000;
    this.render();
    this.input.focus();
  }

  close(): void {
    this.composing = false;
    this.openUntil = 0;
    this.input.blur();
    if (this.state.question) this.onControl("dismissQuestion");
    if (this.state.status === "failed") this.onControl("dismissError");
    this.render();
  }

  get working(): boolean {
    return this.state.status !== "idle" && this.state.status !== "failed";
  }

  private isOpen(): boolean {
    return this.working || this.composing || !!this.state.question || this.state.status === "failed" || performance.now() < this.openUntil;
  }

  private render(): void {
    const s = this.state;
    this.el.classList.toggle("working", this.working);
    this.el.classList.toggle("failed", s.status === "failed");
    this.bubble.classList.toggle("off", !this.isOpen());
    // Words: what it's saying, or what it's doing while it hasn't said anything yet.
    const doing = s.status === "thinking" ? t.enjinThinking() : s.status === "searching" ? t.enjinSearching(s.detail ?? "")
      : s.status === "writing" ? t.enjinBuilding() : "";
    const text = s.text || doing;
    this.words.textContent = text;
    this.words.hidden = !text;
    this.chips.textContent = "";
    if (s.question) {
      const q = document.createElement("b");
      q.textContent = s.question.text;
      this.chips.appendChild(q);
      for (const c of s.question.choices) this.chips.appendChild(this.chip(c, true, () => this.onAnswer(c)));
    } else if (s.status === "idle") {
      for (const st of s.steps) this.chips.appendChild(this.chip(st.dive ? `${st.label} →` : st.label, st.dive, () => this.onStep(st.id)));
    }
    this.chips.hidden = !this.chips.childElementCount;
    this.row.hidden = this.working;
    this.stop.hidden = !this.working;
    this.stop.textContent = t.stop();
    this.undo.hidden = !s.canUndo || this.working;
    this.undo.textContent = t.undo();
    this.input.placeholder = t.askEnjin();
  }

  private chip(label: string, strong: boolean, onTap: () => void): HTMLButtonElement {
    const b = document.createElement("button");
    b.type = "button";
    b.className = strong ? "chip strong" : "chip";
    b.textContent = label;
    b.addEventListener("click", () => { this.openUntil = performance.now() + 4000; onTap(); });
    return b;
  }
}
