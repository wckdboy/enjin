# ENJIN design system

ENJIN ≈ engine, for curious people aged 13 to 25 who are into science and
engineering. The app icon is a hand-drawn three-quarter motor (stator coils
with their windings, rotor, bore). The small mark beside the wordmark and the
spinner is the same motor seen end-on (`docs/enjin-mark.svg`). Everything
follows them: precise, mechatronic, monochrome, for native screens and the
canvas alike.

- **Palette** (`Enjin/Sources/Design/Theme.swift`, mirrored in `canvas-web/src/cards/render.ts`):
  - paper `#FAFAF9`, card `#FFFFFF`, stub `#F2F2F2`, filling `#E9E9E9`
  - ink `#0B0B0C`, ink-soft `#6A6A70`, hairline = ink at 14%
  - The only accent is ink: every "go" (Explore, Send, Dive in, the active tool) is solid black with white text.
  - Drawing inks on the tool rail (ink, ember, sky, leaf) are content, not chrome.
- **Shapes are the mark's:** circles, capsules, concentric rounded rects. No sharp corners, no hard shadows.
- **Type:** **Inter** (OFL, bundled in `Enjin/Resources/Fonts` and `canvas-web/src/assets`).
  - **Inter Display Black**, tracked tight, for display: the wordmark, headings, titles.
  - **Inter** for reading.
  - **Readouts** (`Readout`): SF Mono, capitals, tracked out, for counts, status and "or try". On canvas cards the same role is Cascadia ("3 INSIDE →", "DIVE IN →").
  - Canvas cards are Inter too: Excalidraw's "Helvetica" family (a system font it never loads) is mapped to Inter with `@font-face`. **Excalifont** is only for what the explorer writes.
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
- **Icon:** `tools/icon/motor_bell.py` cleans up the hand-drawn motor (`tools/icon/motor-bell-source.png`): ink/no-ink alpha, contours smoothed at 4×, centred with even padding. It renders the light (black on white, opaque), dark and tinted (white on transparent) icons, plus `MotorHero` (the library's hero art).
- **Mark:** `tools/icon/enjin_mark.py` draws the flat end-on motor as exact geometry (true circles, parallel-sided spokes, one corner radius). It renders the `MotorMark` template image and the SVGs.

## Figures and live models
Cards can carry a **figure** (`visual`) instead of a picture. It is drawn as canvas geometry in the ENJIN look, with a `FIG · KIND` readout (`canvas-web/src/cards/visual.ts`).
- The kinds:
  - **flow**: steps with arrows;
  - **cycle**: stages around a ring;
  - **timeline**;
  - **bars**: switches to a log scale when values are 1000× apart;
  - **parts**: a labelled hub;
  - **stat**: one big number;
  - **formula**: with a symbol legend;
  - **code**;
  - **graph**: a concept map with labelled relations, laid out by a deterministic force layout (`figureMath.ts`);
  - **table**: up to 5 × 6; numeric columns right-aligned in mono;
  - **chart**: line or scatter, up to 3 series, nice ticks or log decades;
  - **live**.
- Figures span two columns (except stat and formula). Each kind has a fixed height, so a figure streaming in item by item never reflows the canvas.
- **Live models** are small interactive simulations and animated dioramas the agent writes as HTML/JS. They run in a sandboxed iframe over the card's slot, following pan and zoom (`LiveLayer.ts`). The sandbox:
  - `sandbox="allow-scripts"` with no same-origin, so the model can't reach the page, its storage or the bridge;
  - a CSP that blocks all network access;
  - the bridge itself refuses non-main frames, and the navigation policy only allows `about:srcdoc` in subframes.
- Live models animate all the time and take touches while their card is selected. A card's detail sheet shows the model at full size in its own sandboxed web view.
- The seeded **Electric motors** sample (`tools/samples/motors.py`, en/da) has every kind except cycle, including a live brushless motor you drive.
- **Visualize:** a button in a filled card's action pill. Enjin turns that card's idea into one figure or live model and places it beside the card.

## Generated pictures
- A card can carry an `illustrate` prompt instead of an image phrase. Image Playground then paints it on the device, for what no photo can show: a cell's interior, a cutaway, deep time. Real things still get real photos from Wikimedia.
- A new notebook gets **cover art**, painted while its first cards are written. It's used as the library cover and the top-level banner.
- Everything, generated or found, goes through the Enjin print shader. Where Image Playground isn't available (simulator, no Apple Intelligence), photos are used instead.

## Language
- English and Danish. Parents choose in Settings (or it follows the iPad); switching is live.
- Native strings are in `Enjin/Resources/Localizable.xcstrings`. Regenerate the key list by building with `SWIFT_EMIT_LOC_STRINGS` and running `xcstringstool sync`.
- Canvas strings are in `canvas-web/src/i18n.ts`; agent/kid messages are `KidStrings` in EnjinKit.
- Claude and the on-device model answer in the chosen language, with image phrases kept in English. The sample notebook has a Danish edition.
