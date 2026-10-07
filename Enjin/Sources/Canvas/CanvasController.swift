import EnjinKit
import Observation
import os
import WebKit

/// Owns the canvas web view and the native side of the bridge.
@MainActor
@Observable
final class CanvasController: NSObject {
    enum Status: Equatable { case loading, ready, failed(String) }

    private(set) var status: Status = .loading
    private(set) var path: [Crumb] = []
    private(set) var focusedCardId: String?
    /// The single selected card, if exactly one is selected.
    private(set) var selectedCardId: String?
    /// Card whose detail sheet should be showing (set by the card's Open action).
    var openCardId: String? {
        // Opening a card is when its body gets written, if Enjin hasn't yet (just in time).
        didSet { if let id = openCardId, id != oldValue { agent.writeBody(for: id) } }
    }
    /// The tool rail's choice.
    private(set) var tool: EnjinTool = .pen
    /// The world (default) or the classic card canvas, fixed when the notebook opens.
    let isWorld: Bool
    private var pageURL: URL { isWorld ? SchemeHandler.worldURL : SchemeHandler.indexURL }
    private(set) var inkColor: Theme.InkColor = Theme.inkColors[0]
    /// Last ink handoff time (stroke end -> rendered on canvas), for the spike HUD.
    var lastInkHandoffMs: Double?

    let webView: WKWebView
    @ObservationIgnored let session: NotebookSession
    let agent: AgentSession
    /// What the explorer does in the world, and Enjin chiming in about it.
    @ObservationIgnored let attention = AttentionLog()
    @ObservationIgnored let companion: Companion
    /// The ask field has the keyboard (Enjin doesn't chime in meanwhile).
    @ObservationIgnored var typing = false
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let telemetry: Telemetry
    @ObservationIgnored private var prefetchTimer: Task<Void, Never>?
    /// Linger this long on a stub before filling it in the background (plan §3.3).
    static let prefetchDelay: Duration = .milliseconds(1500)
    @ObservationIgnored private let router = BridgeRouter()
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "canvas")

    static let expectedExcalidrawVersion = "0.18.1"

    init(session: NotebookSession, settings: AppSettings, telemetry: Telemetry) {
        let bundle = Bundle.main
        self.session = session
        self.settings = settings
        self.telemetry = telemetry
        isWorld = !settings.classicCanvas
        // In the world the Pencil draws (fingers still pan and zoom): sketches Enjin can read and bring to life.
        agent = AgentSession(session: session, backend: settings.makeBackend(), telemetry: telemetry)
        agent.lightBackend = settings.makeLightBackend()
        agent.dailyCapUSD = settings.dailyCapUSD
        agent.imageFinder = settings.makeImageFinder()
        agent.imageGenerator = settings.makeIllustrator()
        agent.imageStylizer = PrintStylizer()
        agent.assist = settings.makeAssist()
        agent.prefetchEnabled = settings.prepareAhead
        agent.language = settings.language
        agent.learner = settings.learner
        agent.attention = attention
        companion = Companion(agent: agent, attention: attention)
        companion.enabled = settings.companion

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(root: bundle.resourceURL!.appendingPathComponent("canvas-web")), forURLScheme: SchemeHandler.scheme)
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "enjin")
        webView.navigationDelegate = self
        webView.isInspectable = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.949, green: 0.949, blue: 0.941, alpha: 1) // Theme.void
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        agent.canvas = self
        registerHandlers()
        webView.load(URLRequest(url: pageURL))
    }

    // MARK: - Native -> web

    @discardableResult
    /// The sandboxed page for a card's live figure (built by the canvas, which has the runtimes).
    func liveDocument(for cardId: String) async -> String? {
        try? await call("canvas.liveDocument", NativeMethod.LiveDocument(cardId: cardId), returning: NativeMethod.LiveDocumentResult.self).html
    }

    func call<P: Encodable, R: Decodable>(_ method: String, _ params: P, returning: R.Type = Empty?.self) async throws -> R {
        seq += 1
        let request = try BridgeRouter.request(id: "n\(seq)", method: method, params: params)
        let raw = try await webView.callAsyncJavaScript(
            "return await window.enjin.handle(req)", arguments: ["req": request.foundationValue], contentWorld: .page)
        return try BridgeRouter.result(try JSONValue(foundation: raw), as: R.self)
    }

    /// Breadcrumb navigation. Going up animates out of the card that leads back down.
    var currentPortalId: String? { path.last?.portalId }

    /// Breadcrumb / map navigation. Going up animates out of the card that leads back down.
    func jump(to portalId: String) {
        guard currentPortalId != portalId else { return }
        let index = path.firstIndex { $0.portalId == portalId }
        let focus = index.flatMap { i in i + 1 < path.count ? session.ownerCardId(of: path[i + 1].portalId) : nil }
        Task {
            do {
                guard let scene = try await session.scene(for: portalId) else { return }
                path = scene.path
                try await call("portal.load", NativeMethod.PortalLoad(scene: scene, transition: index != nil ? .exit : .jump, focusCardId: focus))
            } catch {
                log.error("jump failed: \(error)")
            }
        }
    }

    /// Re-read settings (key, model, cap) after the parent changed them.
    func refreshAgent() {
        agent.backend = settings.makeBackend()
        agent.lightBackend = settings.makeLightBackend()
        agent.dailyCapUSD = settings.dailyCapUSD
        agent.imageFinder = settings.makeImageFinder()
        agent.imageGenerator = settings.makeIllustrator()
        agent.prefetchEnabled = settings.prepareAhead
        companion.enabled = settings.companion
        if agent.language != settings.language {
            agent.language = settings.language
            agent.clearNextSteps()
            Task { _ = try? await call("canvas.setLanguage", NativeMethod.SetLanguage(language: settings.language)) }
        }
    }

    func select(tool: EnjinTool? = nil, color: Theme.InkColor? = nil) {
        if let tool { self.tool = tool }
        if let color { self.inkColor = color }
        sendTool()
    }

    private func sendTool() {
        Task { _ = try? await call("canvas.setTool", NativeMethod.SetTool(tool: tool.canvasTool, color: inkColor.id)) }
    }

    func history(_ action: NativeMethod.History.Action) {
        Task { _ = try? await call("canvas.history", NativeMethod.History(action: action)) }
    }

    func takeNextStep(_ step: AgentSession.NextStep) {
        companion.explorerSpoke()
        agent.clearNextSteps()
        switch step {
        case .ask(let q): ask(q)
        case .dive(let cardId, _): dive(into: cardId)
        }
    }

    func ask(_ text: String) {
        guard let portalId = currentPortalId else { return }
        companion.explorerSpoke()
        agent.ask(text, portalId: portalId, focusCardId: selectedCardId ?? focusedCardId)
    }

    /// The explorer tapped an answer to Enjin's question.
    func answer(_ choice: String) {
        guard let portalId = currentPortalId else { return }
        companion.explorerSpoke()
        agent.answer(choice, portalId: portalId, focusCardId: selectedCardId ?? focusedCardId)
    }

    func goToSuggestion() {
        guard let s = agent.suggestion else { return }
        agent.clearSuggestion()
        Task { _ = try? await call("canvas.frame", NativeMethod.CanvasFrame(cardId: s.cardId), returning: NativeMethod.CanvasFrameResult.self) }
    }

    /// Diving into a stub (or a topic that's empty inside) asks the agent to build
    /// it; cards stream into the new portal. Portals with cards are left alone.
    private func didEnter(_ scene: PortalScene, via cardId: String) {
        prefetchTimer?.cancel()
        Task { await telemetry.record("portal_enter", ["depth": .number(Double(scene.path.count - 1))]) }
        agent.fill(cardId: cardId)
    }

    private func focusChanged(to cardId: String?) {
        prefetchTimer?.cancel()
        guard let cardId, let card = session.card(cardId), card.type == .topic, card.state != .filling else { return }
        prefetchTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.prefetchDelay)
            guard !Task.isCancelled, let self, self.focusedCardId == cardId else { return }
            self.agent.prefetch(cardId: cardId)
        }
    }

    /// Edit a card's text and re-render it in place.
    func updateCard(_ id: String, title: String, summary: String, body: String?) async {
        do {
            guard let card = try await session.updateCard(id, {
                $0.title = title
                $0.summary = summary
                $0.body = body
            }) else { return }
            // A renamed card also renames its portal, which shows in the breadcrumb.
            if let portalId = currentPortalId { path = session.path(to: portalId) }
            try await call("canvas.applyOps", NativeMethod.ApplyOps(portalId: card.portalId, ops: [.upsert(session.bridgeCard(card))]),
                           returning: NativeMethod.ApplyOpsResult.self)
        } catch {
            log.error("updateCard failed: \(error)")
        }
    }

    /// Dive into a card from native UI (e.g. the detail sheet).
    func dive(into cardId: String) {
        Task {
            do {
                guard let scene = try await session.enter(cardId: cardId) else { return }
                path = scene.path
                selectedCardId = nil
                didEnter(scene, via: cardId)
                // focusCardId tells the canvas which card to zoom through.
                try await call("portal.load", NativeMethod.PortalLoad(scene: scene, transition: .dive, focusCardId: cardId))
            } catch {
                log.error("dive failed: \(error)")
            }
        }
    }

    /// Kid-made card in the portal on screen.
    func createCard(type: CardType, title: String, summary: String) async {
        guard let portalId = currentPortalId else { return }
        do {
            let card = try await session.createCard(in: portalId, type: type, title: title, summary: summary, author: .kid)
            await telemetry.record("card_created", ["by": .string("kid")])
            defer { Task { await agent.decorateKidCard(card.id) } }
            try await call("canvas.applyOps",
                           NativeMethod.ApplyOps(portalId: portalId, ops: [.upsert(session.bridgeCard(card))]),
                           returning: NativeMethod.ApplyOpsResult.self)
            _ = try? await call("canvas.flash", NativeMethod.CanvasFlash(cardId: card.id))
        } catch {
            log.error("createCard failed: \(error)")
        }
    }

    // MARK: - Web -> native

    private func registerHandlers() {
        router.on("canvas.ready", WebMethod.CanvasReady.self) { [weak self] p in
            guard let self else { return WebMethod.CanvasReadyResult(accepted: false) }
            guard p.protocolVersion == bridgeProtocolVersion else {
                let reason = "Canvas speaks bridge v\(p.protocolVersion), app speaks v\(bridgeProtocolVersion). Rebuild canvas-web."
                status = .failed(reason)
                return WebMethod.CanvasReadyResult(accepted: false, reason: reason)
            }
            if p.excalidrawVersion != Self.expectedExcalidrawVersion {
                log.warning("Excalidraw \(p.excalidrawVersion), expected \(Self.expectedExcalidrawVersion)")
            }
            status = .ready
            Task { await self.loadInitialPortal() }
            return WebMethod.CanvasReadyResult(accepted: true)
        }
        router.on("portal.enter", WebMethod.PortalEnter.self) { [weak self] p in
            self?.selectedCardId = nil
            guard let self, let scene = try await session.enter(cardId: p.cardId) else { return PortalScene?.none }
            path = scene.path
            didEnter(scene, via: p.cardId)
            return scene
        }
        router.on("portal.peek", WebMethod.PortalPeek.self) { [weak self] p in
            guard let self else { return PortalScene?.none }
            return try await session.peek(cardId: p.cardId)
        }
        router.on("portal.zoomInto", WebMethod.PortalZoomInto.self) { [weak self] p in
            self?.selectedCardId = nil
            guard let self, let into = try await session.zoomInto(portalId: p.portalId, title: p.title, detail: p.detail, cardId: p.cardId)
            else { return WebMethod.PortalZoomIntoResult?.none }
            path = into.scene.path
            didEnter(into.scene, via: into.cardId)
            return WebMethod.PortalZoomIntoResult(scene: into.scene, cardId: into.cardId)
        }
        router.on("portal.exit", WebMethod.PortalExit.self) { [weak self] p in
            self?.selectedCardId = nil
            guard let self, let out = try await session.exit(from: p.portalId) else { return WebMethod.PortalExitResult?.none }
            path = out.scene.path
            return WebMethod.PortalExitResult(scene: out.scene, focusCardId: out.focusCardId)
        }
        router.on("canvas.changed", WebMethod.CanvasChanged.self) { [weak self] p in
            try await self?.session.saveElements(portalId: p.portalId, elements: p.elements)
            return Empty()
        }
        router.on("focus.changed", WebMethod.FocusChanged.self) { [weak self] p in
            guard let self else { return Empty() }
            if focusedCardId != p.cardId {
                focusedCardId = p.cardId
                focusChanged(to: p.cardId)
            }
            return Empty()
        }
        router.on("media.stylize", WebMethod.MediaStylize.self) { [weak self] p in
            // Pasted/dropped images get the same ENJIN look as everything else.
            guard let comma = p.dataURL.firstIndex(of: ","), let data = Data(base64Encoded: String(p.dataURL[p.dataURL.index(after: comma)...])) else {
                throw BridgeError(code: BridgeErrorCode.invalidParams.rawValue, message: "not a base64 data URL")
            }
            let found = FoundImage(data: data, mimeType: p.mimeType, width: 0, height: 0, credit: nil, sourceURL: "pasted")
            let styled = await (self?.agent.imageStylizer ?? PrintStylizer()).stylize(found)
            return WebMethod.MediaStylize(dataURL: "data:\(styled.mimeType);base64,\(styled.data.base64EncodedString())", mimeType: styled.mimeType)
        }
        router.on("card.open", WebMethod.CardOpen.self) { [weak self] p in
            self?.openCardId = p.cardId
            return Empty()
        }
        router.on("card.visualize", WebMethod.CardVisualize.self) { [weak self] p in
            guard let self, let portalId = self.currentPortalId else { return Empty() }
            Task { await self.telemetry.record("visualize") }
            self.agent.visualize(cardId: p.cardId, portalId: portalId)
            return Empty()
        }
        router.on("selection.changed", WebMethod.SelectionChanged.self) { [weak self] p in
            self?.selectedCardId = p.cardIds.count == 1 ? p.cardIds[0] : nil
            return Empty()
        }
        // The Pencil in the world: a drawing is kept where it was drawn; writing is read and answered.
        router.on("sketch.add", WebMethod.SketchAdd.self) { [weak self] p in
            guard let self, let comma = p.png.firstIndex(of: ","), let png = Data(base64Encoded: String(p.png[p.png.index(after: comma)...])),
                  let size = UIImage(data: png)?.size else {
                throw BridgeError(code: BridgeErrorCode.invalidParams.rawValue, message: "not a PNG data URL")
            }
            let reading = await HandwritingReader.read(png)
            let card = try await session.addSketch(in: p.portalId, png: png, place: p.place, text: reading?.text,
                                                   width: Int(size.width), height: Int(size.height))
            if let image = card.image, let file = await session.bridgeFile(image) { _ = try? await call("canvas.addFiles", NativeMethod.AddFiles(files: [file])) }
            _ = try? await call("canvas.applyOps", NativeMethod.ApplyOps(portalId: p.portalId, ops: [.upsert(session.bridgeCard(card))]),
                                returning: NativeMethod.ApplyOpsResult.self)
            Task { await self.telemetry.record("sketch", ["writing": .bool(reading?.isWriting ?? false)]) }
            // Writing is talking to Enjin: it reads it and answers on the canvas.
            if let reading, reading.isWriting, p.portalId == currentPortalId {
                companion.explorerSpoke()
                agent.ask("(wrote by hand on the canvas) \(reading.text)", portalId: p.portalId, focusCardId: card.id)
            }
            return WebMethod.SketchAddResult(cardId: card.id)
        }
        router.on("sketch.bringToLife", WebMethod.SketchBringToLife.self) { [weak self] p in
            guard let self, let image = session.card(p.cardId)?.image,
                  let png = await session.store.file(session.id, fileId: image.fileId) else { return Empty() }
            companion.explorerSpoke()
            Task { await self.telemetry.record("bring_to_life") }
            agent.bringToLife(sketchId: p.cardId, png: png)
            return Empty()
        }
        // The character on the canvas talks to Enjin.
        router.on("enjin.ask", WebMethod.EnjinAsk.self) { [weak self] p in
            self?.ask(p.text)
            return Empty()
        }
        router.on("enjin.answer", WebMethod.EnjinAnswer.self) { [weak self] p in
            self?.answer(p.choice)
            return Empty()
        }
        router.on("enjin.step", WebMethod.EnjinStep.self) { [weak self] p in
            guard let self, let step = agent.nextSteps.first(where: { Self.stepId($0, in: self.agent.nextSteps) == p.id }) else { return Empty() }
            takeNextStep(step)
            return Empty()
        }
        router.on("enjin.control", WebMethod.EnjinControl.self) { [weak self] p in
            guard let self else { return Empty() }
            switch p.action {
            case .stop: agent.cancel()
            case .undo: Task { await self.agent.undoLastTurn() }
            case .dismissQuestion: agent.dismissQuestion()
            case .dismissError: agent.dismissError()
            }
            return Empty()
        }
        router.on("enjin.typing", WebMethod.EnjinTyping.self) { [weak self] p in
            self?.typing = p.typing
            return Empty()
        }
        router.on("attention", WebMethod.Attention.self) { [weak self] p in
            guard let self else { return Empty() }
            attention.record(p.events, in: p.portalId)
            if p.portalId == currentPortalId { companion.consider(portalId: p.portalId, typing: typing) }
            return Empty()
        }
        router.on("log.event", WebMethod.LogEvent.self) { [weak self] p in
            switch p.level {
            case .error: self?.log.error("web: \(p.message)")
            case .warn: self?.log.warning("web: \(p.message)")
            default: self?.log.info("web: \(p.message)")
            }
            return Empty()
        }
    }

    // MARK: - Enjin on the canvas

    static func stepId(_ step: AgentSession.NextStep, in steps: [AgentSession.NextStep]) -> String {
        switch step {
        case .dive(let cardId, _): "dive:\(cardId)"
        case .ask(let q): "ask:\(steps.firstIndex(of: .ask(q)) ?? 0)"
        }
    }

    /// What the character on the canvas shows: Enjin's status, words, question and offers.
    var enjinState: NativeMethod.EnjinState {
        let steps = agent.isRunning ? [] : agent.nextSteps.map { s -> NativeMethod.EnjinState.Step in
            switch s {
            case .dive(_, let title): .init(id: Self.stepId(s, in: agent.nextSteps), label: title, dive: true)
            case .ask(let q): .init(id: Self.stepId(s, in: agent.nextSteps), label: q, dive: false)
            }
        }
        let question = agent.isRunning ? nil : agent.question.map { NativeMethod.EnjinState.Question(text: $0.text, choices: $0.choices) }
        switch agent.status {
        case .failed(let message): return .init(status: .failed, text: message)
        case .working(.thinking): return .init(status: .thinking, text: agent.reply)
        case .working(.searching(let q)): return .init(status: .searching, text: agent.reply, detail: q.isEmpty ? nil : q)
        case .working(.writing): return .init(status: .writing, text: agent.reply)
        case .idle: return .init(status: .idle, text: agent.reply, question: question, steps: steps, canUndo: agent.canUndo && !agent.isRunning)
        }
    }

    /// Keep the character in step with Enjin: a few times a second, only when something changed.
    private func streamEnjin() {
        presenceTask?.cancel()
        guard isWorld else { return }
        presenceTask = Task { [weak self] in
            var last: NativeMethod.EnjinState?
            while !Task.isCancelled {
                guard let self else { return }
                let now = self.enjinState
                if now != last, self.status == .ready {
                    last = now
                    _ = try? await self.call("enjin.state", now)
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func loadInitialPortal() async {
        // After a web process crash, come back to where the kid was.
        let portalId = path.last?.portalId ?? session.rootPortalId
        _ = try? await call("canvas.setLanguage", NativeMethod.SetLanguage(language: settings.language))
        // Keep cards clear of the floating chrome: top bar, tool rail, dock.
        _ = try? await call("canvas.setInsets", NativeMethod.SetInsets(top: 84, left: 96, bottom: 150, right: 24))
        sendTool()
        streamEnjin()
        do {
            guard let scene = try await session.scene(for: portalId) else { return }
            path = scene.path
            try await call("portal.load", NativeMethod.PortalLoad(scene: scene, transition: .jump))
            // A brand-new notebook opens itself up.
            if session.data.cards.isEmpty && agent.backend != nil && !agent.isRunning { agent.begin(portalId: portalId) }
        } catch {
            status = .failed("Couldn't load the canvas: \(error.localizedDescription)")
        }
    }
}

extension CanvasController: WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        // Only the canvas page itself may talk to native. Live models run in
        // sandboxed iframes (model-written code) and must never reach the bridge.
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == SchemeHandler.scheme else {
            return (nil, "not allowed")
        }
        do {
            let request = try JSONValue(foundation: message.body)
            return (await router.handle(request).foundationValue, nil)
        } catch {
            return (nil, "bad message: \(error)")
        }
    }
}

extension CanvasController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = action.request.url
        if url?.scheme == SchemeHandler.scheme { return .allow }
        // Live models: sandboxed srcdoc iframes. Nothing else may load, in any frame.
        if action.targetFrame?.isMainFrame == false, url?.absoluteString == "about:srcdoc" { return .allow }
        return .cancel
    }

    /// iOS kills the web process under memory pressure. Native is the source of
    /// truth, so this is recoverable: reload and rehydrate the same portal.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("web content process terminated; reloading")
        status = .loading
        webView.load(URLRequest(url: pageURL))
    }
}

extension CanvasController: CanvasSink {
    func apply(portalId: String, ops: [CardOp]) async {
        do {
            try await call("canvas.applyOps", NativeMethod.ApplyOps(portalId: portalId, ops: ops), returning: NativeMethod.ApplyOpsResult.self)
        } catch {
            log.error("applyOps failed: \(error)")
        }
    }

    func flash(cardId: String) async {
        _ = try? await call("canvas.flash", NativeMethod.CanvasFlash(cardId: cardId))
    }

    func addFiles(_ files: [BridgeFile]) async {
        _ = try? await call("canvas.addFiles", NativeMethod.AddFiles(files: files))
    }

    func setHeader(_ header: NativeMethod.SetHeader) async {
        _ = try? await call("canvas.setHeader", header)
    }

    func setBusy(portalId: String, message: String?) async {
        _ = try? await call("canvas.setBusy", NativeMethod.SetBusy(portalId: portalId, message: message))
    }
}
