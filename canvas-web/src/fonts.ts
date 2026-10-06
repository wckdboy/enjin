// Excalidraw only loads scene fonts for `initialData`; scenes we set later via
// updateScene render (and get measured) in the fallback font forever. So load
// every Excalifont face before any card is built. Excalidraw registers its
// FontFaces shortly after mount, so wait for them to appear first.
let ready: Promise<void> | null = null;

// Excalifont for the kid's own text; Lilita One and Nunito for cards.
const FAMILIES = new Set(["Excalifont", "Lilita One", "Nunito"]);
const excalifontFaces = () => Array.from(document.fonts).filter((f) => FAMILIES.has(f.family.replace(/["']/g, "")));

export function ensureFonts(timeoutMs = 3000): Promise<void> {
  ready ??= Promise.race([
    (async () => {
      const deadline = performance.now() + timeoutMs;
      const families = () => new Set(excalifontFaces().map((f) => f.family.replace(/["']/g, "")));
      while (families().size < FAMILIES.size && performance.now() < deadline) await new Promise((r) => setTimeout(r, 25));
      const faces = excalifontFaces();
      if (faces.length === 0) console.warn("[fonts] no Excalifont faces registered");
      await Promise.all(faces.map((f) => f.load().catch(() => undefined)));
    })(),
    new Promise<void>((r) => setTimeout(r, timeoutMs)),
  ]);
  return ready;
}
