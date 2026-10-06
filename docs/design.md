# ENJIN design system

One visual language for native screens and the canvas.

- **Palette** (`Enjin/Sources/Design/Theme.swift`, mirrored in `canvas-web/src/cards/render.ts`):
  - paper `#FFFAF0` (backgrounds), card `#FFF4E6`, stub `#F1F3F5`
  - ink `#2A2A3C` (text, outlines), ink-soft `#5C5F73`
  - ember `#E8590C`: the one accent, used for every "go" (Explore, Send, Dive in, the active tool, cues). Ember-soft `#FFE8D9` marks cards being filled.
- **Type:**
  - **Lilita One** for display: the wordmark, headings, card titles on the canvas, portal titles. Bundled unmodified, OFL 1.1 (`Enjin/Resources/Fonts/OFL-LilitaOne.txt`).
  - **SF Rounded** for reading in native UI; **Nunito** for summaries on the canvas (they look alike).
  - **Excalifont** only for what the kid writes with the text tool: their own hand.
- **Stickers:** surfaces and buttons have a paper fill, a 2pt ink outline, and a hard ink shadow offset by (3,4). Buttons press into the page (the shadow collapses). Same treatment on the web: card-action pill, busy hint.
- **Canvas chrome is native:**
  - top-left: back plus breadcrumb sticker;
  - top-right: New card, Map, Settings;
  - left: tool rail (select, pen, highlighter, text, box, arrow, eraser, 4 inks, undo/redo);
  - bottom: Enjin dock.
  - Excalidraw's own UI is hidden (`.layer-ui__wrapper`). The rail drives it through `canvas.setTool` / `canvas.history`, and the canvas frames content clear of the chrome (`canvas.setInsets`). Pen and highlighter ink with Pencil through PencilKit; other tools let Pencil act on the canvas directly.
- **Pictures:** every imported image goes through the "Enjin print" Metal kernel (posterized brightness, original colors, ink edges, paper highlights, grain).
- **Icon:** the ember "E" sticker with a spark (`Assets.xcassets/AppIcon`).

## Language
- English and Danish. Parents choose in Settings (or it follows the iPad); switching is live.
- Native strings are in `Enjin/Resources/Localizable.xcstrings`. Regenerate the key list by building with `SWIFT_EMIT_LOC_STRINGS` and running `xcstringstool sync`.
- Canvas strings are in `canvas-web/src/i18n.ts`; agent/kid messages are `KidStrings` in EnjinKit.
- Claude and the on-device model answer in the chosen language, with image phrases kept in English. The sample notebook has a Danish edition (`shared/demo-notebook.da.json`).
