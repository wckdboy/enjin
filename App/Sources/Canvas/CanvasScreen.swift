import EnjinKit
import SwiftUI

struct CanvasScreen: View {
    let controller: CanvasController
    @Environment(\.dismiss) private var dismiss
    @State private var tool: InkTool = .pen
    @State private var routing: InkRouting = .relocatedRecognizer
    @State private var showAgentSpike = false
    @State private var showMap = false
    @State private var showNewCard = false
    @State private var openCardId: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Notebooks")
                BreadcrumbBar(path: controller.path) { controller.jump(to: $0) }
                Spacer()
                Button { showNewCard = true } label: { Image(systemName: "plus.rectangle.on.rectangle") }
                    .accessibilityLabel("New card")
                    .disabled(controller.status != .ready)
                Button { showMap = true } label: { Image(systemName: "map") }
                    .accessibilityLabel("Map")
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

            ZStack(alignment: .bottom) {
                CanvasRepresentable(controller: controller, tool: tool, routing: routing)
                if let id = controller.selectedCardId, let card = controller.session.card(id) {
                    Button { openCardId = id } label: {
                        Label("Open “\(card.title)”", systemImage: "rectangle.portrait.and.arrow.forward")
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .sheet(isPresented: $showMap) {
            MapView(session: controller.session, current: controller.currentPortalId) { portalId in
                showMap = false
                controller.jump(to: portalId)
            }
        }
        .animation(.snappy, value: controller.selectedCardId)
        .sheet(item: Binding(get: { openCardId.map(IdentifiedString.init) }, set: { openCardId = $0?.id })) { item in
            if let card = controller.session.card(item.id) {
                CardDetailSheet(card: card,
                                onSave: { t, s, b in Task { await controller.updateCard(card.id, title: t, summary: s, body: b) } },
                                onDive: card.type == .topic ? { openCardId = nil; controller.dive(into: card.id) } : nil)
            }
        }
        .sheet(isPresented: $showNewCard) {
            NewCardSheet { type, title, summary in
                Task { await controller.createCard(type: type, title: title, summary: summary) }
            }
        }
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
