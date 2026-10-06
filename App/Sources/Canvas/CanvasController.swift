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
    /// Last ink handoff time (stroke end -> rendered on canvas), for the spike HUD.
    var lastInkHandoffMs: Double?

    let webView: WKWebView
    @ObservationIgnored let notebook: DemoNotebook
    @ObservationIgnored private let router = BridgeRouter()
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private let log = Logger(subsystem: "cc.wckd.enjin", category: "canvas")

    static let expectedExcalidrawVersion = "0.18.1"

    override init() {
        let bundle = Bundle.main
        let demoURL = bundle.url(forResource: "demo-notebook", withExtension: "json")!
        notebook = try! DemoNotebook(data: Data(contentsOf: demoURL))

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
    func jump(to portalId: String) {
        guard let current = path.last, current.portalId != portalId, let scene = notebook.scene(for: portalId) else { return }
        let index = path.firstIndex { $0.portalId == portalId }
        let focus = index.flatMap { i in i + 1 < path.count ? notebook.ownerCardId(of: path[i + 1].portalId) : nil }
        path = scene.path
        Task {
            do {
                try await call("portal.load", NativeMethod.PortalLoad(scene: scene, transition: index != nil ? .exit : .jump, focusCardId: focus))
            } catch {
                log.error("portal.load failed: \(error)")
            }
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
            guard let self, let scene = notebook.enter(cardId: p.cardId) else { return PortalScene?.none }
            path = scene.path
            return scene
        }
        router.on("portal.exit", WebMethod.PortalExit.self) { [weak self] p in
            guard let self, let out = notebook.exit(from: p.portalId) else { return WebMethod.PortalExitResult?.none }
            path = out.scene.path
            return WebMethod.PortalExitResult(scene: out.scene, focusCardId: out.focusCardId)
        }
        router.on("canvas.changed", WebMethod.CanvasChanged.self) { [weak self] p in
            self?.notebook.save(portalId: p.portalId, elements: p.elements)
            return Empty()
        }
        router.on("focus.changed", WebMethod.FocusChanged.self) { [weak self] p in
            self?.focusedCardId = p.cardId
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
        let portalId = path.last?.portalId ?? notebook.rootPortalId
        guard let scene = notebook.scene(for: portalId) else { return }
        path = scene.path
        do {
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
