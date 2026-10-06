# ENJIN design system

ENJIN ≈ engine. The app icon is a monochrome electric motor (a cylinder, one
seam, a shaft), and everything else follows it: one engineered, monochrome
visual language for native screens and the canvas.

- **Palette** (`Enjin/Sources/Design/Theme.swift`, mirrored in `canvas-web/src/cards/render.ts`):
  - paper `#FAFAF9`, card `#FFFFFF`, stub `#F2F2F2`, filling `#E9E9E9`
  - ink `#0B0B0C`, ink-soft `#6A6A70`
  - The only accent is ink: every "go" (Explore, Send, Dive in, the active tool) is solid black with white text.
  - Drawing inks on the tool rail (ink, ember, sky, leaf) are content, not chrome.
- **Type:**
  - **SF Pro Expanded Black** for display: the wordmark, headings, card titles in sheets.
  - **SF Pro** for reading.
  - **Helvetica** on canvas cards.
  - **Excalifont** only for what the kid writes with the text tool.
- **Mark:** the motor from the icon (`Assets.xcassets/MotorMark`, a template image) sits beside the ENJIN wordmark. Bolts (⚡) stand for "Enjin is doing something".
- **Stickers:** surfaces and buttons have a 2pt black outline and a hard black shadow offset by (3,4), and press into the page when tapped. Corner radius 12.
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
- **Icon:** `tools/icon/motor_icon.py` renders the light (black on white, opaque), dark and tinted (white on transparent) variants.

## Language
- English and Danish. Parents choose in Settings (or it follows the iPad); switching is live.
- Native strings are in `Enjin/Resources/Localizable.xcstrings`. Regenerate the key list by building with `SWIFT_EMIT_LOC_STRINGS` and running `xcstringstool sync`.
- Canvas strings are in `canvas-web/src/i18n.ts`; agent/kid messages are `KidStrings` in EnjinKit.
- Claude and the on-device model answer in the chosen language, with image phrases kept in English. The sample notebook has a Danish edition.
