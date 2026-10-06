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
