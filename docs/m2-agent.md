# M2: agent on canvas, status

Built and tested against a scripted model (no API key available here).

## What happens
- **Ask:** the kid types in the dock. A turn composes the prompt (`PromptComposer`: current portal in full, siblings by title, the rest as counts; the kid's changes since last time; a 3-turn tail from other portals). It runs the model with `createCards`, `updateCard`, `suggestFocus` and web search. Cards appear as each tool call completes.
- **Dive into a stub:** the stub turns blue (`filling`) and the portal opens immediately. The agent fills the stub and adds 2–4 cards inside, which land in the open portal. Cards that arrive mid-animation wait for it to finish.
- **Linger on a stub for 1.5s:** it's prefetched in the background, so diving in is instant. Prefetches never show in the dock and never become the "undo" target.
- **Undo:** the dock's undo button reverts Enjin's last visible turn: created cards are removed (never resurrected by a late canvas save) and updated cards restored.
- **Stop:** cancels the turn. Cards already placed stay; a stub being filled goes back to a stub.

## Guardrails
- At most 4 cards per call and 6 per turn. Text is clipped to the limits instead of failing the call.
- Enjin can't edit the kid's cards; the tool returns an error explaining why.
- Cards can only cite URLs the model actually saw in this turn's search results.
- Threads restart after 8 turns instead of trimming history, because edited history invalidates thinking blocks.
- A daily spend cap (default $2, set by a parent) is computed from local telemetry with per-model pricing.
- A parent consent screen must be accepted before any key is used. The key is stored in Keychain, this device only.
- Errors shown to the kid are plain words: no key, bad key, busy, offline, resting for today, can't help with that.

## Backends
- **Claude** (`AnthropicBackend`): defaults to Opus 5.5 at low effort; Sonnet 5.5 / Haiku 4.5 are selectable in Settings. Server-side refusal fallback is on, and web search uses a kid-safety domain blocklist.
- **On-device** (`AppleFMBackend`, Foundation Models): no key needed. It uses a compact persona and prompt, only `createCards`/`updateCard`, and no web or prefetch. It's used automatically when no key is set and Apple Intelligence is available.
- **UI test** (`UITestBackend`, debug builds, `-uiTestingFakeAgent`): deterministic.

## Needs you
- [ ] Add a key in Settings (gear in the library). Run the worked example: "Roman Empire" → dive "Legions" → "why did Rome win so much?" Record turn latency and cost from `telemetry.jsonl` (Application Support).
- [ ] Choose the default model from those numbers.
- [ ] Build the 25-prompt eval set (plan §8) once real turns can be run.

## Live cards and pictures (added 2026-10-06)
- **Cards build on screen while Enjin writes.** `createCards` input streams in (`eager_input_streaming`) and is parsed as partial JSON (`PartialJSON`). Each card appears as soon as its title exists, and its summary types in at about 8 updates per second. The finished card keeps the preview's id and position, so nothing jumps. Previews from a cancelled turn, or ones dropped by the caps, are removed.
- **Pictures.** The model gives filled cards an `image` phrase. `WikimediaImages` searches Wikipedia, takes the lead image of the best-matching article (`pilicense=free`, at least 160px), and records attribution (artist and license from Commons). It skips pictures already used in the notebook and screens title, file name, description and Commons categories against a word blocklist. Live check (`ENJIN_LIVE=1 swift test --filter LiveWikimedia`): Roman legionary, Colosseum, Via Appia and testudo all found.
- On the canvas, picture cards reserve their space with a "finding a picture…" placeholder, so arriving images never push other cards around. Images are cover-cropped (portraits keep their upper part) and new cards are placed masonry-style.
- Images are saved in `notebooks/<id>/files/`, sent to the canvas as data URLs (`canvas.addFiles`, `PortalScene.files`), and shown large in the card's detail sheet with credit, a "About this picture" link, and the card's sources.
- Parents can turn pictures off in Settings.

## Faster, cheaper, guided, coherent (added 2026-10-06)
Real-key telemetry showed 7–26s turns at $0.05–0.13 each, with 2–3 rounds per turn, up to 3 searches, and background prefetches (5 of 8 turns) the kid never asked for.
- **One round per turn.** The reply comes first, then all tool calls; the turn ends once client tools succeed (`endAfterClientTools`). Their results open the next user message. Failed tools still get a retry round. Tested against stubbed SSE.
- **At most one web search,** and only for facts the model is unsure of.
- **Prefetch is off by default** ("Prepare cards ahead" in Settings). Cache-write tokens are now logged per turn.
- **Apple's on-device model (free):** next-question chips after each turn, and picture phrases for cards without one (stubs, the kid's own cards).
- **Guidance:** new notebooks open themselves (a `begin` turn), with "Enjin is exploring…" shown in empty portals. Chips offer "dive into" for new stubs plus two questions. Stubs say "dive in →", and explored cards say "N inside →". A one-time pinch tip appears. Excalidraw's hints, menu, library, help and rarely-used tools are hidden.
- **Visuals:** a portal opens with the owner card's picture as a banner plus its summary. Cards have a title/summary type hierarchy. Every card can have a picture.
- **Pictures:** facts prefer real Wikipedia photos; stubs and kid cards prefer on-device Image Playground illustrations (needs an Apple Intelligence iPad; falls back to photos). Everything passes through the "Enjin print" Core Image Metal kernel (`Enjin/Sources/Media/EnjinPrint.metal`) at import: posterized brightness with original chroma kept, ink edges (Sobel), ink-tinted shadows, highlights melting into the paper color, and grain. That gives one sketchbook look.
