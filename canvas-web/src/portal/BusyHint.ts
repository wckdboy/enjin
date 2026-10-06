/** A small pulsing pill in the middle of an empty portal while Enjin fills it. */
export class BusyHint {
  private el: HTMLDivElement;

  constructor() {
    this.el = document.createElement("div");
    this.el.dataset.enjin = "busy";
    this.el.style.display = "none";
    this.el.innerHTML = `<span></span><i></i><i></i><i></i>`;
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
