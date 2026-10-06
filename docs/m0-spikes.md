# M0 spikes — status

Each spike gets a written go/no-go (plan §10). Status as of 2026-10-06.

## 1. Offline canvas + versioned bridge — ✅ go

- canvas-web is bundled into the app and served via `WKURLSchemeHandler` on `enjin://app/`. No network needed.
- Handshake: `canvas.ready {protocolVersion, excalidrawVersion}`. A version mismatch shows a hard error screen.
- JSON-RPC both ways. Web→native uses `WKScriptMessageHandlerWithReply`; native→web uses `callAsyncJavaScript`, with arguments passed as objects (no string escaping).
- Unknown method → -32601, wrong version → -32000, bad params → -32602. Tested on both sides.
- Contract: `shared/bridge-fixtures/*.json` is generated from the zod schema. Both vitest and Swift tests decode and round-trip every method.
- If the web process dies, the controller reloads and rehydrates the same portal (`webViewWebContentProcessDidTerminate`).
- Verified in the iPad simulator: root portal renders through `enjin://` and the canvas is ready in ~265ms.

Finding: Excalidraw only loads fonts for `initialData`. Scenes set through `updateScene` render and wrap in the fallback serif font forever. Fix in `canvas-web/src/fonts.ts`: wait for Excalifont faces to be registered, load them, then send `canvas.ready`.

## 2. Ink handoff — ⏳ needs a real iPad + Pencil

Built:
- A PencilKit overlay that only ever holds strokes still in flight.
- On stroke end, `ink.commit` sends view-space points, pressure and width. Web converts them with its own viewport, inserts a `freedraw` element, and replies after the next paint. Native then removes its copy.
- `ink.lock` blocks finger pan/pinch while the pencil is down.
- Web drops every pen-type pointer/touch event, so Excalidraw never sees the Pencil.
- Two touch-routing strategies are switchable from the 🐞 menu:
  - `relocatedRecognizer` (default): the overlay ignores hit-testing, and its drawing recognizer lives on the container view.
  - `hitTestFilter`: the overlay is hit-testable only for touches that include a Pencil.
- The 🐞 menu shows the last handoff time.

Already tested in WebKit (Playwright): stroke placement at 2× zoom with scroll, lock blocking pan, pen events not reaching Excalidraw, and ink saved to the right portal even if you dive within the 500ms debounce.

On device, check:
- [ ] Which routing strategy works. Delete the other one.
- [ ] No visible flicker when the native stroke is swapped for the canvas stroke. Watch closely on fast short strokes.
- [ ] The committed stroke matches what was drawn: position and thickness at 0.5×, 1× and 3× zoom. Width mapping is `width / zoom / 4.25`; tune `FREEDRAW_SIZE_FACTOR` if needed.
- [ ] A palm resting while drawing doesn't pan the canvas.
- [ ] Finger pan, pinch, and Excalidraw's own tools still work with the overlay in place.
- [ ] Handoff time in the 🐞 menu is comfortably < 50ms.

Fallback if these fail: Excalidraw's built-in freedraw with Pencil pointer events (remove `ink.commit` and the pen filter in `inputGate.ts`).

## 3. Portals — ⏳ needs a kid's opinion

**Update (2026-10-06):** the fade-and-pop transition read as changing pages. It has been replaced by a continuous zoom:
- The camera flies into a window inside the card (with the screen's aspect ratio). The child portal, pre-rendered with `exportToCanvas` into exactly its framed view, fades in inside that window. When the window fills the screen, the real scene swaps in at the same pixels (measured mean difference 0.34/255).
- Exit is the reverse: the current child view shrinks back into the card's window while the parent pulls into view.
- Camera flights are anchored on the card. Its screen position moves in a straight line while zoom changes geometrically, so it never swings around.
- The preview sits between Excalidraw's canvases and its UI, so toolbars never blink.
- Selecting a card shows a small "Dive in / Open" pill on the card itself, instead of a floating button and Excalidraw's style panel.

Original notes:

Built: three nested portals (Roman Empire › Legions › Why Rome won so much › Logistics).
- Dive in by pinching a topic card until it fills about 80% of the screen (you must also be zoomed in at least 1.3× past the fitted view), or by double-tapping it.
- Pinching out below 55% of the fitted zoom exits to the parent portal.
- Breadcrumb taps play the exit animation, framed on the card you came from.
- Transitions: 160ms camera move into the card, 180ms fade-out, 260ms grow-in. Exit plays in reverse with a 420ms camera pull-back.

Tested in WebKit: dive three levels and exit by zoom-out.

On device, check:
- [ ] Pinch-to-dive triggers reliably mid-gesture, with no zoom jump after the swap. The input gate swallows the rest of the gesture until fingers lift.
- [ ] Ask a kid: does it feel like zooming *into* something, or like changing pages?
- [ ] No accidental dives while just looking closely at a card. If it happens, raise `DIVE_AT` or require a double-tap.

Known M0 shortcuts: cards are `locked` (can't be moved or edited), the demo notebook is hard-coded, and nothing persists across launches.

## 4. Anthropic adapter — ⏳ needs an API key run

Built: raw `URLSession` SSE streaming (there is no Swift SDK) and a manual tool loop.
- Custom tool `createCards` with `eager_input_streaming`. Inputs are validated by the loop, and invalid JSON goes back to the model as an `is_error` result.
- Server web search: `web_search_20260209` on Opus/Sonnet 5.5, `web_search_20250305` on Haiku, with a domain blocklist and `max_uses`.
- Every block is echoed back verbatim (thinking + signatures, server tool blocks, citations), so the transcript stays append-only.
- Handles `pause_turn`, `refusal` and `max_tokens`. Never runs tools from a truncated turn.
- Retries 429/529/5xx before the first streamed byte (never mid-stream).
- Top-level `cache_control` for prompt caching.
- On Opus/Sonnet: `fallbacks: "default"` plus the `server-side-fallback-2026-07-01` beta, so a refusal falls back to another model server-side.
- The API key is stored in Keychain, this device only.

Tested: SSE replay of every block type, invalid tool JSON, web-search error objects, stream errors, request bodies per model.

To do:
- [ ] 🐞 → Agent spike: run the same prompt on Opus 5.5 (low effort), Sonnet 5.5 and Haiku 4.5. Record first-event ms, total ms, tokens and cache reads.
- [ ] Pick the model. This decides whether dive-time filling of stubs (plan §3.3) can meet p50 < 2s for first content.
- [ ] Check citations come back for factual claims.
