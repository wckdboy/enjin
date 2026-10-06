import EnjinKit
import SwiftUI
import UIKit

/// The front page: what do you want to explore, and your notebooks as covers.
struct LibraryView: View {
    @State private var library: Library
    let settings: AppSettings
    let telemetry: Telemetry
    @State private var open: [String] = []
    @State private var topic = ""
    /// How deep new notebooks go; remembered between launches.
    @AppStorage("explore.level") private var level: ExplorerLevel = .student
    @State private var showSettings = false
    @State private var confirmDelete: NotebookMeta?
    @FocusState private var topicFocused: Bool

    init(store: NotebookStore, settings: AppSettings, telemetry: Telemetry) {
        _library = State(initialValue: Library(store: store))
        self.settings = settings
        self.telemetry = telemetry
    }

    /// Starter topics (English keys; shown and started in the current language).
    private static let starterKeys = ["How AI learns", "Robots", "Black holes", "CRISPR", "How a CPU works", "Electric motors",
                                      "The human brain", "Quantum computers"]
    private var starters: [LocalizedStringKey] { Self.starterKeys.map { LocalizedStringKey($0) } }

    var body: some View {
        NavigationStack(path: $open) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    HStack(alignment: .center) {
                        Wordmark(size: 52)
                        Spacer()
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .buttonStyle(RotorKeyStyle())
                            .accessibilityLabel(Text("Settings"))
                            .accessibilityIdentifier("settings")
                    }

                    explorePrompt

                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Your notebooks") {
                            Readout(text: Text("\(library.notebooks.count) notebooks"))
                        }
                        if library.notebooks.isEmpty {
                            emptyShelf
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 26)], alignment: .leading, spacing: 30) {
                                ForEach(library.notebooks) { nb in
                                    NavigationLink(value: nb.id) {
                                        NotebookCover(meta: nb, cover: library.covers[nb.id], cardCount: library.counts[nb.id] ?? 0)
                                    }
                                    .buttonStyle(CoverPressStyle())
                                    .contextMenu {
                                        Button(role: .destructive) { confirmDelete = nb } label: { Label("Delete notebook", systemImage: "trash") }
                                    }
                                    .accessibilityIdentifier("notebook:\(nb.title)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(FieldBackground(depth: true).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                NotebookScreen(notebookId: id, store: library.store, settings: settings, telemetry: telemetry)
                    .onDisappear { Task { await library.refresh() } }
            }
            .sheet(isPresented: $showSettings) { SettingsView(settings: settings, telemetry: telemetry) }
            .confirmationDialog(Text("Delete this notebook?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible, presenting: confirmDelete) { nb in
                Button("Delete “\(nb.title)”", role: .destructive) { Task { await library.delete(nb.id) } }
            } message: { _ in
                Text("All its cards, drawings and pictures will be gone.")
            }
            .task {
                await library.load(language: settings.language)
                #if DEBUG
                // Screenshots/previews: jump straight into the first notebook.
                if ProcessInfo.processInfo.arguments.contains("-openFirstNotebook"), let first = library.notebooks.first { open = [first.id] }
                #endif
            }
        }
        .tint(Theme.accent)
    }

    /// The launch console: a bracketed glass panel with the logo lit from behind.
    private var explorePrompt: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Readout("Science · Engineering · Code")
                    Heading(text: "What do you want to explore?", size: 46)
                    Text("Enjin builds the notebook as you go: pick a depth, then follow the rabbit holes.")
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.fgSoft)
                }
                Spacer(minLength: 0)

            }
            HStack(spacing: 14) {
                TextField(text: $topic) { Text("A topic, a question, anything…").foregroundStyle(Theme.fgFaint) }
                    .font(Theme.body(21))
                    .foregroundStyle(Theme.fg)
                    .tint(Theme.signal)
                    .focused($topicFocused)
                    .submitLabel(.go)
                    .onSubmit { start(topic) }
                    .padding(.horizontal, 22)
                    .frame(height: 58)
                    .wellCapsule(focused: topicFocused)
                    .accessibilityIdentifier("topicField")
                Button { start(topic) } label: {
                    Label("Explore", systemImage: "arrow.right").labelStyle(TrailingIcon())
                }
                .buttonStyle(KeyButtonStyle(kind: .primary, size: .large))
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("explore")
            }
            HStack(spacing: 14) {
                Readout("Depth")
                GearSelector(selection: $level, options: [
                    (.curious, "Curious", "sparkles"),
                    (.student, "Student", "graduationcap"),
                    (.expert, "Expert", "atom"),
                ])
                .accessibilityIdentifier("levelPicker")
            }
            SignalLine()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Readout("or try")
                    ForEach(starters.indices, id: \.self) { i in
                        Button { start(starterText(i)) } label: { Text(starters[i]) }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, size: .small))
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 6)
            }
        }
        .padding(36)
        .panel(radius: 34)
    }

    /// No notebooks yet.
    private var emptyShelf: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing here yet").font(Theme.title(20)).foregroundStyle(Theme.fg)
                Text("Pick a topic above. Enjin writes the first cards, and every card you dive into grows the notebook.")
                    .font(Theme.body(15)).foregroundStyle(Theme.fgSoft)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.edge, style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
    }

    /// The starter's text in the current language (the key itself is English).
    private func starterText(_ i: Int) -> String {
        Self.starterKeys[i].localizedIn(settings.language)
    }

    private func start(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        topic = ""
        topicFocused = false
        Task { if let id = await library.create(title: t, level: level) { open = [id] } }
    }
}

/// A notebook as a glass card: its cover art (or the logo while it has none),
/// its title, depth and size.
struct NotebookCover: View {
    let meta: NotebookMeta
    let cover: UIImage?
    let cardCount: Int
    var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.deck
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    // No picture yet: the notebook's initial, large and quiet.
                    Text(String(meta.title.prefix(1)).uppercased())
                        .font(Theme.display(96))
                        .foregroundStyle(Theme.fg.opacity(0.12))
                }
            }
            .frame(height: 168)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
            .padding([.horizontal, .top], 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(meta.title)
                    .font(Theme.display(24))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    if let level = meta.level {
                        Readout(text: Text(level.label), color: Theme.fg)
                        Text(verbatim: "·").foregroundStyle(Theme.fgFaint)
                    }
                    Readout(text: Text("\(cardCount) cards"), color: Theme.fg)
                    Text(verbatim: "·").foregroundStyle(Theme.fgFaint)
                    Readout(text: Text(meta.updatedAt, format: .relative(presentation: .named)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect(cornerRadius: 22))
    }
}

/// Covers press like keys: they dip, and their edge lights.
struct CoverPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .panel(radius: 22, active: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: configuration.isPressed) { _, now in now }
    }
}

/// Opens a notebook from disk, then shows its canvas.
struct NotebookScreen: View {
    let notebookId: String
    let store: NotebookStore
    let settings: AppSettings
    let telemetry: Telemetry
    @State private var controller: CanvasController?
    @State private var error: String?

    var body: some View {
        Group {
            if let controller {
                CanvasScreen(controller: controller)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open notebook", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            do {
                controller = CanvasController(session: try await NotebookSession.open(notebookId, store: store),
                                              settings: settings, telemetry: telemetry)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Title first, icon after: "Explore →".
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) { configuration.title; configuration.icon }
    }
}

extension ExplorerLevel {
    var label: LocalizedStringKey {
        switch self {
        case .curious: "Curious"
        case .student: "Student"
        case .expert: "Expert"
        }
    }
}
