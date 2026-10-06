import EnjinKit
import SwiftUI

struct CanvasScreen: View {
    @State private var controller = CanvasController()
    @State private var tool: InkTool = .pen
    @State private var routing: InkRouting = .relocatedRecognizer
    @State private var showAgentSpike = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                BreadcrumbBar(path: controller.path) { controller.jump(to: $0) }
                Spacer()
                InkPalette(tool: $tool)
                Menu {
                    Picker("Pencil routing", selection: $routing) {
                        ForEach(InkRouting.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button("Agent spike…") { showAgentSpike = true }
                    if let ms = controller.lastInkHandoffMs {
                        Text(String(format: "Last ink handoff: %.1f ms", ms))
                    }
                } label: {
                    Image(systemName: "ladybug")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)

            ZStack {
                CanvasRepresentable(controller: controller, tool: tool, routing: routing)
                switch controller.status {
                case .loading: ProgressView()
                case .ready: EmptyView()
                case .failed(let reason):
                    ContentUnavailableView("Canvas failed to start", systemImage: "exclamationmark.triangle", description: Text(reason))
                        .background(.background)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showAgentSpike) { AgentSpikeView() }
    }
}

struct BreadcrumbBar: View {
    let path: [Crumb]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(path.enumerated()), id: \.element.portalId) { i, crumb in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    Button(crumb.title) { onTap(crumb.portalId) }
                        .buttonStyle(.plain)
                        .font(i == path.count - 1 ? .headline : .body)
                        .foregroundStyle(i == path.count - 1 ? .primary : .secondary)
                        .disabled(i == path.count - 1)
                }
            }
        }
        .animation(.snappy, value: path)
    }
}

struct InkPalette: View {
    @Binding var tool: InkTool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InkTool.allCases) { t in
                Button { tool = t } label: {
                    Image(systemName: t == .highlighter ? "highlighter" : "pencil.tip")
                        .foregroundStyle(t == .blue ? .blue : t == .highlighter ? .yellow : .primary)
                        .frame(width: 36, height: 36)
                        .background(tool == t ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rawValue)
            }
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let controller: CanvasController
    let tool: InkTool
    let routing: InkRouting

    func makeUIView(context: Context) -> CanvasContainerView {
        CanvasContainerView(controller: controller)
    }

    func updateUIView(_ view: CanvasContainerView, context: Context) {
        view.setTool(tool)
        view.setRouting(routing)
    }
}
