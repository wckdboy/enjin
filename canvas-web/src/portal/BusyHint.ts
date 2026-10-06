import logo from "../assets/enjin-logo.png";

/** A glass pill with the turning logo, in the middle of an empty portal while Enjin fills it. */
export class BusyHint {
  private el: HTMLDivElement;

  constructor() {
    this.el = document.createElement("div");
    this.el.dataset.enjin = "busy";
    this.el.className = "enjin-glass";
    this.el.style.display = "none";
    this.el.innerHTML = `<img alt="" src="${logo}"><span></span>`;
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
