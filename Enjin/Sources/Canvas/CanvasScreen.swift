import EnjinKit
import SwiftUI

/// The canvas, full-bleed, with ENJIN's chrome floating on it: where you are
/// (top-left), what you can add (top-right), how you draw (left rail), and
/// Enjin itself (bottom).
struct CanvasScreen: View {
    let controller: CanvasController
    @Environment(\.dismiss) private var dismiss
    @State private var routing: InkRouting = .relocatedRecognizer
    @State private var showAgentSpike = false
    @State private var showMap = false
    @State private var showNewCard = false
    @State private var showSettings = false
    @AppStorage("tip.dive.seen") private var diveTipSeen = false

    var body: some View {
        ZStack {
            CanvasRepresentable(controller: controller, routing: routing)
                .ignoresSafeArea()

            if case .failed(let reason) = controller.status {
                ContentUnavailableView {
                    Label("The canvas didn't start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                }
                .background(Theme.paper)
            } else if controller.status == .loading {
                ProgressView().tint(Theme.ember)
            }
        }
        .overlay(alignment: .topLeading) { navigation.padding(.leading, 20).padding(.top, 12) }
        .overlay(alignment: .topTrailing) { actions.padding(.trailing, 20).padding(.top, 12) }
        .overlay(alignment: .leading) {
            if controller.status == .ready { ToolRail(controller: controller).padding(.leading, 20) }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if !diveTipSeen && controller.status == .ready && controller.agent.nextSteps.contains(where: \.isDive) {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.pinch").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ember)
                        Text("Tip: pinch a card open, or tap it and press **Dive in**, to go inside it.")
                            .font(Theme.body(16)).foregroundStyle(Theme.ink)
                        Button("Got it") { diveTipSeen = true }.buttonStyle(StickerButtonStyle(kind: .primary))
                    }
                    .padding(14)
                    .sticker(Theme.paper)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if controller.status == .ready {
                    AgentDock(agent: controller.agent, onAsk: controller.ask, onGoToSuggestion: controller.goToSuggestion,
                              onNextStep: controller.takeNextStep)
                }
            }
            .padding(.bottom, 20)
            .padding(.horizontal, 96)
        }
        .background(Theme.paper)
        .animation(.snappy, value: diveTipSeen)
        .sheet(isPresented: $showAgentSpike) { AgentSpikeView() }
        .sheet(isPresented: $showSettings, onDismiss: controller.refreshAgent) {
            SettingsView(settings: controller.settings, telemetry: controller.telemetry)
        }
        .sheet(item: Binding(get: { controller.openCardId.map(IdentifiedString.init) }, set: { controller.openCardId = $0?.id })) { item in
            if let card = controller.session.card(item.id) {
                CardDetailSheet(card: card,
                                onSave: { t, s, b in Task { await controller.updateCard(card.id, title: t, summary: s, body: b) } },
                                onDive: card.type == .topic ? { controller.openCardId = nil; controller.dive(into: card.id) } : nil,
                                loadImage: { image in
                                    await controller.session.store.file(controller.session.id, fileId: image.fileId).flatMap(UIImage.init(data:))
                                })
            }
        }
        .onChange(of: showMap) { _, open in
            if open { Task { await controller.telemetry.record("map_opened") } }
        }
        .sheet(isPresented: $showMap) {
            MapView(session: controller.session, current: controller.currentPortalId) { portalId in
                showMap = false
                controller.jump(to: portalId)
            }
        }
        .sheet(isPresented: $showNewCard) {
            NewCardSheet { type, title, summary in
                Task { await controller.createCard(type: type, title: title, summary: summary) }
            }
        }
    }

    /// Back to the notebooks, and the path of portals you dived through.
    private var navigation: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)) }
                .buttonStyle(IconButtonStyle(size: 40))
                .accessibilityLabel(Text("Notebooks"))
                .accessibilityIdentifier("notebooks")
                .padding(.trailing, 8)
            ForEach(Array(controller.path.enumerated()), id: \.element.portalId) { i, crumb in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ember) }
                if i == controller.path.count - 1 {
                    Text(crumb.title)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button { controller.jump(to: crumb.portalId) } label: {
                        Text(crumb.title)
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("crumb:\(crumb.title)")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .sticker(Theme.paper, radius: 26)
        .animation(.snappy, value: controller.path)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { showNewCard = true } label: { Image(systemName: "plus") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(Text("New card"))
                .accessibilityIdentifier("newCard")
                .disabled(controller.status != .ready)
            Button { showMap = true } label: { Image(systemName: "map") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(Text("Map"))
                .accessibilityIdentifier("map")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("settings")
            #if DEBUG
            Menu {
                Picker(selection: $routing) {
                    ForEach(InkRouting.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                } label: { Text(verbatim: "Pencil routing") }
                Button { showAgentSpike = true } label: { Text(verbatim: "Agent spike…") }
                if let ms = controller.lastInkHandoffMs { Text(verbatim: String(format: "Last ink handoff: %.1f ms", ms)) }
            } label: { Image(systemName: "ladybug") }
                .buttonStyle(IconButtonStyle())
            #endif
        }
    }
}

/// Drawing tools, colors, undo/redo: ENJIN's replacement for Excalidraw's toolbar.
struct ToolRail: View {
    let controller: CanvasController

    var body: some View {
        VStack(spacing: 6) {
            ForEach(EnjinTool.allCases) { t in
                Button { controller.select(tool: t) } label: { Image(systemName: t.symbol) }
                    .buttonStyle(RailButtonStyle(active: controller.tool == t))
                    .accessibilityLabel(Text(t.label))
                    .accessibilityAddTraits(controller.tool == t ? .isSelected : [])
            }
            Divider().frame(width: 30).overlay(Theme.ink.opacity(0.25)).padding(.vertical, 4)
            ForEach(Theme.inkColors) { c in
                Button { controller.select(color: c) } label: {
                    Circle().fill(c.color).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: controller.inkColor == c ? 3 : 1.5))
                        .padding(4)
                        .overlay(Circle().strokeBorder(controller.inkColor == c ? Theme.ink : .clear, lineWidth: 1.5))
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(c.name))
                .accessibilityAddTraits(controller.inkColor == c ? .isSelected : [])
            }
            Divider().frame(width: 30).overlay(Theme.ink.opacity(0.25)).padding(.vertical, 4)
            Button { controller.history(.undo) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(RailButtonStyle()).accessibilityLabel(Text("Undo"))
            Button { controller.history(.redo) } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(RailButtonStyle()).accessibilityLabel(Text("Redo"))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .sticker(Theme.paper, radius: 28)
    }
}

struct RailButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(active ? Color.white : Theme.ink)
            .frame(width: 44, height: 44)
            .background(active ? Theme.ember : (configuration.isPressed ? Theme.card : .clear), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? Theme.ink : .clear, lineWidth: Theme.line))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
            .contentShape(.rect)
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let controller: CanvasController
    let routing: InkRouting

    func makeUIView(context: Context) -> CanvasContainerView {
        CanvasContainerView(controller: controller)
    }

    func updateUIView(_ view: CanvasContainerView, context: Context) {
        view.setTool(controller.tool, color: controller.inkColor.color)
        view.setRouting(routing)
    }
}
