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
    /// Last ink handoff time (stroke end -> rendered on canvas), for the spike HUD.
    var lastInkHandoffMs: Double?

    let webView: WKWebView
    @ObservationIgnored let session: NotebookSession
    @ObservationIgnored private let router = BridgeRouter()
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "canvas")

    static let expectedExcalidrawVersion = "0.18.1"

    init(session: NotebookSession) {
        let bundle = Bundle.main
        self.session = session

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(root: bundle.resourceURL!.appendingPathComponent("canvas-web")), forURLScheme: SchemeHandler.scheme)
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "enjin")
        webView.navigationDelegate = self
        webView.isInspectable = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 1, green: 0.992, blue: 0.973, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        registerHandlers()
        webView.load(URLRequest(url: SchemeHandler.indexURL))
    }

    // MARK: - Native -> web

    @discardableResult
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
                try await call("portal.load", NativeMethod.PortalLoad(scene: scene, transition: .dive))
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
            return scene
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
            self?.focusedCardId = p.cardId
            return Empty()
        }
        router.on("selection.changed", WebMethod.SelectionChanged.self) { [weak self] p in
            self?.selectedCardId = p.cardIds.count == 1 ? p.cardIds[0] : nil
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

    private func loadInitialPortal() async {
        // After a web process crash, come back to where the kid was.
        let portalId = path.last?.portalId ?? session.rootPortalId
        do {
            guard let scene = try await session.scene(for: portalId) else { return }
            path = scene.path
            try await call("portal.load", NativeMethod.PortalLoad(scene: scene, transition: .jump))
        } catch {
            status = .failed("Couldn't load the canvas: \(error.localizedDescription)")
        }
    }
}

extension CanvasController: WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
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
        action.request.url?.scheme == SchemeHandler.scheme ? .allow : .cancel
    }

    /// iOS kills the web process under memory pressure. Native is the source of
    /// truth, so this is recoverable: reload and rehydrate the same portal.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("web content process terminated; reloading")
        status = .loading
        webView.load(URLRequest(url: SchemeHandler.indexURL))
    }
}
