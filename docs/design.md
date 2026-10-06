# ENJIN design system

ENJIN ≈ engine, for curious people aged 13 to 25 who are into science and
engineering. The look is **white, black and glass**:
- a soft light field;
- frosted white Liquid Glass with a bright edge and a soft lift;
- black type;
- black for the one thing to press, or for what's selected.

The chrome has no colour; colour belongs to content (drawing inks, pictures). The
logo, the hand-drawn three-quarter motor from the app icon, is the only mark.
It is used everywhere a logo appears: the wordmark, section headers, the
spinner, empty states, cover placeholders, and the canvas's busy hint. It also
sits huge behind the library's glass.

- **Kit** (`Enjin/Sources/Design/`; open `-designKit` in debug builds to see every piece):
  - `Theme.swift`: tokens and type.
  - `Surfaces.swift`: glass `panel()`/`chrome()`, `well()`, and `FieldBackground`.
  - `Keys.swift`: primary keys are solid black, secondary ones glass, round icon keys and rail tools; all with haptics.
  - `Controls.swift`: `GearSelector` and fields.
  - `Marks.swift`: `Logo`, `Wordmark`, `Rotor` (the logo, turning while Enjin works), `Readout`, `Heading`, `SectionHeader`, `SignalLine`, `SignalMeter`.
  - The canvas mirrors the tokens in `canvas-web/src/cards/palette.ts`.
- **Type:** **Inter** (OFL, bundled): Inter Display Bold for display, Inter for reading, SF Mono capitals for readouts. Canvas cards are Inter too, via Excalidraw's "Helvetica" family, mapped with `@font-face`.
- **Cards** on the canvas are white faces with a fine edge and a 20pt inner margin. A card being written gets a black edge; stubs are dashed.
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
- **Icon and logo:** `tools/icon/motor_bell.py` cleans up the hand-drawn motor (`tools/icon/motor-bell-source.png`). It renders the app icons, `MotorHero` (the logo as a template image), and `canvas-web/src/assets/enjin-logo.png`.

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
## Skills: the media Enjin chooses
The agent picks, for each idea, the medium that makes it clearest. The skills are defined in `AgentTools.visual` and `Persona.system`:
- **Figures** (above): structure and real numbers.
- **3D models** (`model3d`): models from primitives (box, sphere, cylinder, cone, torus, ring), with labels and motion (spin, orbit). They're drawn by ENJIN's own small engine (`canvas-web/src/live/engine3d.ts`): drag to turn, pinch to zoom.
- **Dioramas** (`diorama`): 2.5D scenes in depth layers with parallax, animated props and hotspots. A backdrop painted on the device is optional (`live/diorama.ts`).
- **Generative UI** (`ui`): interactive learning widgets the agent designs on the fly from a component kit. The components are sliders, toggles, choices, readouts, meters, plots, quizzes, steps, flashcards, ordering games and rows (`live/uiKit.ts`). Formulas run through a safe expression compiler (`live/expr.ts`, no `eval`).
- **Illustrations**: pictures painted on the device (Image Playground).
- **Live code**: the agent's own HTML/JS, for what no skill can show.

Skills are data (a JSON `spec`), so they're reliable and always on-style. They run in the same sandbox as live code: ENJIN's runtime source is injected (`live/documents.ts`). The animated runtimes keep a timer watchdog, because WebKit can withhold animation frames from a sandboxed frame.

- Nothing is pre-built: every notebook is generated live by Enjin from the topic the explorer types and the **depth** they choose (Curious, Student or Expert, stored per notebook and sent with every turn), then grown by their dives and questions. The hand-made **Electric motors** notebook (`tools/samples/motors.py`, en/da) is a test and dev fixture only: `-seedSample` in debug builds, `?fixture=motors` in the dev host.
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
