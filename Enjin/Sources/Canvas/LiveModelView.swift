import SwiftUI
import WebKit

/// A live model (agent-written HTML simulation) at full size, outside the canvas.
/// Same isolation as on the canvas: its own web view with no bridge, an ephemeral
/// data store, a CSP that blocks all network access, and no navigation away.
struct LiveModelView: UIViewRepresentable {
    let html: String

    static let csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:"

    /// Mirrors canvas-web's liveDocument (LiveLayer.ts): CSP first, then a requestAnimationFrame
    /// that survives an odd throwing frame, then the model.
    static func document(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        <script>(function(){var raf=window.requestAnimationFrame.bind(window),fails=0;
        window.requestAnimationFrame=function(cb){return raf(function tick(t){try{cb(t);fails=0}catch(e){if(++fails<300)raf(tick)}})};})();</script>
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#fff;color:#0b0b0c;
        font:15px -apple-system,system-ui,sans-serif;-webkit-user-select:none;user-select:none;touch-action:none}</style>
        </head><body>\(html)</body></html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.loadHTMLString(Self.document(html), baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loaded = false
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // The initial load only; links and redirects go nowhere.
            defer { loaded = true }
            return loaded ? .cancel : .allow
        }
    }
}
