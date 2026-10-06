# Enjin

iPad canvas for curious kids: an Excalidraw canvas in a WKWebView, a PencilKit
ink layer, and a Claude agent that grows the canvas into nested "portals" you
dive into. Plan: [docs/plan.md](docs/plan.md). Current milestone: **M0 spikes**
([docs/m0-spikes.md](docs/m0-spikes.md)).

```
canvas-web/   React + Excalidraw (pinned 0.18.1), bridge client, portals, ink commit
EnjinKit/     Swift package: bridge types/router, demo notebook, Anthropic client + agent loop
App/          SwiftUI shell: WKWebView over enjin://, PencilKit overlay, breadcrumb, agent spike
shared/       bridge fixtures (generated) + demo notebook, read by both sides
```

```sh
make setup      # once
make app        # build web bundle + Xcode project + simulator build
make test       # tsc + vitest, swift test, Playwright (WebKit)
open Enjin.xcodeproj   # run on a real iPad for the Pencil spike
```

Bridge changes: edit `canvas-web/src/bridge/schema.ts`, mirror in
`EnjinKit/Sources/EnjinKit/Bridge/Messages.swift`, then `make fixtures test`.
The contract tests on both sides fail if they drift.
