import UniformTypeIdentifiers
import WebKit

/// Serves the bundled canvas-web build at enjin://app/… so the page has a real
/// origin (fonts and module scripts load without file:// restrictions) and
/// never touches the network.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "enjin"
    static let indexURL = URL(string: "enjin://app/index.html")!
    /// The 3D world (same bridge as the card canvas).
    static let worldURL = URL(string: "enjin://app/world.html")!

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let path = url.path.isEmpty || url.path == "/" ? "/index.html" : url.path
        let file = root.appendingPathComponent(path).standardizedFileURL
        // Refuse anything that escapes the bundle directory.
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
            task.didFinish()
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["Content-Type": mime, "Content-Length": "\(data.count)", "Cache-Control": "no-cache"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
