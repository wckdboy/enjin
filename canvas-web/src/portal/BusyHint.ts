import mark from "../assets/enjin-mark.svg?raw";

/** A glass pill with the turning rotor, in the middle of an empty portal while Enjin fills it. */
export class BusyHint {
  private el: HTMLDivElement;

  constructor() {
    this.el = document.createElement("div");
    this.el.dataset.enjin = "busy";
    this.el.className = "enjin-glass";
    this.el.style.display = "none";
    this.el.innerHTML = `${mark}<span></span>`;
  }

  show(message: string | null): void {
    if (!this.el.isConnected) (document.querySelector(".excalidraw") ?? document.body).appendChild(this.el);
    if (!message) {
      this.el.style.display = "none";
      return;
    }
    this.el.querySelector("span")!.textContent = message;
    this.el.style.display = "flex";
  }
}
