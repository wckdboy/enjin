# ENJIN design system

ENJIN ≈ engine. The mark is a motor seen end-on: a housing ring, six coils
between six spokes, the rotor ring and the bore (`docs/enjin-mark.svg`).
Everything follows it: precise, mechatronic, monochrome, for native screens
and the canvas alike.

- **Palette** (`Enjin/Sources/Design/Theme.swift`, mirrored in `canvas-web/src/cards/render.ts`):
  - paper `#FAFAF9`, card `#FFFFFF`, stub `#F2F2F2`, filling `#E9E9E9`
  - ink `#0B0B0C`, ink-soft `#6A6A70`, hairline = ink at 14%
  - The only accent is ink: every "go" (Explore, Send, Dive in, the active tool) is solid black with white text.
  - Drawing inks on the tool rail (ink, ember, sky, leaf) are content, not chrome.
- **Shapes are the mark's:** circles, capsules, concentric rounded rects. No sharp corners, no hard shadows.
- **Type:**
  - **SF Pro Expanded Black** for display: the wordmark, headings, titles.
  - **SF Pro** for reading.
  - **Readouts** (`Readout`): SF Mono, capitals, tracked out, for counts, status and "or try". On canvas cards the same role is Cascadia ("3 INSIDE →", "DIVE IN →").
  - **Helvetica** for card text on the canvas; **Excalifont** only for what the kid writes.
- **Surfaces:**
  - Content (explore panel, notebook covers, sheets) sits on **machined panels** (`.panel()`): white, a 1pt hairline edge, a soft contact shadow.
  - Chrome floating over the canvas (crumbs, actions, tool rail, dock, tips) is **Liquid Glass** (`.chrome()`, `.glassEffect`). Icon buttons are glass circles; active ones are ink-tinted glass.
  - On the web side, the card actions pill and the busy hint use `.enjin-glass`, a backdrop-filter version of the same material.
  - The library sits on engineering paper (`DotGrid`).
- **Motion:** the mark is the busy indicator (`Rotor`). It steps round one coil (60°) at a time, like a stepper motor, natively and on the canvas. Buttons scale down slightly when pressed.
- **Dividers** on the tool rail are three short ticks, like a scale on a dial.
- **Canvas chrome is native:**
  - top-left: back plus breadcrumb;
  - top-right: New card, Map, Settings;
  - left: tool rail;
  - bottom: Enjin dock.
  - Excalidraw's UI is hidden and driven through `canvas.setTool` / `canvas.history`. Content is framed clear of the chrome (`canvas.setInsets`).
- **Pictures, one look:** every picture goes through the "Enjin print" Core Image Metal kernel (`Enjin/Sources/Media/EnjinPrint.metal`) before it's saved: Wikipedia photos, Image Playground illustrations, and images pasted or dropped onto the canvas (`media.stylize`). The kernel applies:
  - posterized brightness (print layers);
  - Sobel ink edges;
  - ink-black shadows;
  - highlights melting into paper;
  - grain;
  - 55% of the original color: muted, so pictures sit calmly in the monochrome UI.
- **Icon:** `tools/icon/enjin_mark.py` draws the mark as exact geometry (true circles, parallel-sided spokes, one corner radius) and renders the light (black on white, opaque), dark and tinted (white on transparent) app icons, the `MotorMark` template image, and the SVGs.

## Language
- English and Danish. Parents choose in Settings (or it follows the iPad); switching is live.
- Native strings are in `Enjin/Resources/Localizable.xcstrings`. Regenerate the key list by building with `SWIFT_EMIT_LOC_STRINGS` and running `xcstringstool sync`.
- Canvas strings are in `canvas-web/src/i18n.ts`; agent/kid messages are `KidStrings` in EnjinKit.
- Claude and the on-device model answer in the chosen language, with image phrases kept in English. The sample notebook has a Danish edition.
