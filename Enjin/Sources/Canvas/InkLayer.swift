import EnjinKit
import os
import PencilKit
import SwiftUI
import UIKit

/// The tools on ENJIN's rail. Pen and highlighter ink with Pencil through
/// PencilKit (and with a finger through the canvas); every other tool lets
/// Pencil act on the canvas like a finger.
enum EnjinTool: String, CaseIterable, Identifiable {
    case select, pen, highlighter, text, box, arrow, eraser
    var id: String { rawValue }

    var isInk: Bool { self == .pen || self == .highlighter }

    var canvasTool: NativeMethod.SetTool.Tool {
        switch self {
        case .select: .selection
        case .pen: .freedraw
        case .highlighter: .highlighter
        case .text: .text
        case .box: .rectangle
        case .arrow: .arrow
        case .eraser: .eraser
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .box: "square"
        case .arrow: "arrow.up.right"
        case .eraser: "eraser"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .select: "Select"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .box: "Box"
        case .arrow: "Arrow"
        case .eraser: "Eraser"
        }
    }

    func pkTool(color: UIColor) -> PKInkingTool {
        self == .highlighter ? PKInkingTool(.marker, color: color.withAlphaComponent(0.9), width: 18) : PKInkingTool(.pen, color: color, width: 3)
    }
}

/// How Pencil touches reach PencilKit without stealing finger touches from the web view.
/// Both are candidates in the M0 spike; keep the winner, delete the other.
enum InkRouting: String, CaseIterable, Identifiable {
    /// Overlay ignores hit-testing; its drawing recognizer is moved to the container.
    case relocatedRecognizer
    /// Overlay is hit-testable only for touches that include a Pencil.
    case hitTestFilter
    var id: String { rawValue }
}

final class PassthroughCanvasView: PKCanvasView {
    var filterFingers = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard filterFingers else { return super.hitTest(point, with: event) }
        guard let touches = event?.allTouches, touches.contains(where: { $0.type == .pencil }) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Web view + PencilKit overlay. The overlay only ever holds strokes that are
/// in flight: once the canvas confirms it rendered a stroke, we drop our copy.
@MainActor
final class CanvasContainerView: UIView, PKCanvasViewDelegate {
    let ink = PassthroughCanvasView()
    private let controller: CanvasController
    private let log = Logger(subsystem: "cc.wckd.enjin", category: "ink")

    private var knownStrokeCount = 0
    private var inFlight = 0
    private var toolActive = false
    private var mutatingDrawing = false

    init(controller: CanvasController) {
        self.controller = controller
        super.init(frame: .zero)
        let web = controller.webView
        web.translatesAutoresizingMaskIntoConstraints = false
        ink.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        addSubview(ink)
        for v in [web, ink] {
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        ink.drawingPolicy = .pencilOnly
        ink.isOpaque = false
        ink.backgroundColor = .clear
        ink.isScrollEnabled = false
        ink.contentInsetAdjustmentBehavior = .never
        ink.delegate = self
        ink.tool = EnjinTool.pen.pkTool(color: UIColor(Theme.ink))
        setRouting(.relocatedRecognizer)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pen/highlighter: Pencil inks here. Anything else: Pencil goes to the canvas.
    func setTool(_ tool: EnjinTool, color: Color) {
        if tool.isInk { ink.tool = tool.pkTool(color: UIColor(color)) }
        ink.drawingGestureRecognizer.isEnabled = tool.isInk
    }

    private var routing: InkRouting?

    func setRouting(_ routing: InkRouting) {
        guard routing != self.routing else { return }
        self.routing = routing
        let recognizer = ink.drawingGestureRecognizer
        recognizer.view?.removeGestureRecognizer(recognizer)
        switch routing {
        case .relocatedRecognizer:
            ink.isUserInteractionEnabled = false
            ink.filterFingers = false
            addGestureRecognizer(recognizer)
        case .hitTestFilter:
            ink.isUserInteractionEnabled = true
            ink.filterFingers = true
            ink.addGestureRecognizer(recognizer)
        }
    }

    // MARK: PKCanvasViewDelegate

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        toolActive = true
        Task { try? await controller.call("ink.lock", NativeMethod.InkLock(locked: true)) }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        toolActive = false
        if inFlight == 0 { unlock() }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !mutatingDrawing else { return }
        let strokes = canvasView.drawing.strokes
        defer { knownStrokeCount = strokes.count }
        guard strokes.count > knownStrokeCount else { return }
        for stroke in strokes[knownStrokeCount...] { commit(stroke) }
    }

    // MARK: Handoff

    private func commit(_ stroke: PKStroke) {
        let started = CACurrentMediaTime()
        let created = stroke.path.creationDate
        var points: [[Double]] = []
        var pressures: [Double] = []
        var widthSum = 0.0
        for p in stroke.path.interpolatedPoints(by: .distance(1.5)) {
            let loc = p.location.applying(stroke.transform)
            points.append([loc.x, loc.y])
            pressures.append(min(1, max(0.1, p.force / 3)))
            widthSum += p.size.width
        }
        guard !points.isEmpty else { return }
        let params = NativeMethod.InkCommit(
            strokeId: UUID().uuidString,
            tool: stroke.ink.inkType == .marker ? .highlighter : .pen,
            color: stroke.ink.color.hexString,
            width: widthSum / Double(points.count),
            points: points,
            pressures: pressures)
        inFlight += 1
        Task {
            defer {
                inFlight -= 1
                if inFlight == 0 && !toolActive { unlock() }
            }
            do {
                _ = try await controller.call("ink.commit", params, returning: NativeMethod.InkCommitResult.self)
                removeStroke(createdAt: created)
                controller.lastInkHandoffMs = (CACurrentMediaTime() - started) * 1000
            } catch {
                // Keep the native stroke visible rather than lose the kid's ink.
                log.error("ink.commit failed: \(error)")
            }
        }
    }

    private func removeStroke(createdAt: Date) {
        var drawing = ink.drawing
        guard let i = drawing.strokes.firstIndex(where: { $0.path.creationDate == createdAt }) else { return }
        drawing.strokes.remove(at: i)
        mutatingDrawing = true
        ink.drawing = drawing
        mutatingDrawing = false
        knownStrokeCount = drawing.strokes.count
    }

    private func unlock() {
        Task { try? await controller.call("ink.lock", NativeMethod.InkLock(locked: false)) }
    }
}

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}
