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
                            .buttonStyle(IconButtonStyle())
                            .accessibilityLabel(Text("Settings"))
                            .accessibilityIdentifier("settings")
                    }

                    explorePrompt

                    if !library.notebooks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline) {
                                Heading(text: "Your notebooks", size: 30)
                                Spacer()
                                Readout(text: Text("\(library.notebooks.count) notebooks"))
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 24)], alignment: .leading, spacing: 28) {
                                ForEach(library.notebooks) { nb in
                                    NavigationLink(value: nb.id) {
                                        NotebookCover(meta: nb, cover: library.covers[nb.id], cardCount: library.counts[nb.id] ?? 0)
                                    }
                                    .buttonStyle(.plain)
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
            .background(DotGrid().ignoresSafeArea())
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

    private var explorePrompt: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Readout("Science · Engineering · Code")
                    Heading(text: "What do you want to explore?", size: 44)
                }
                Spacer(minLength: 0)
                Image("MotorHero")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                TextField(text: $topic) { Text("A topic, a question, anything…") }
                    .font(Theme.body(22))
                    .foregroundStyle(Theme.ink)
                    .focused($topicFocused)
                    .submitLabel(.go)
                    .onSubmit { start(topic) }
                    .padding(.horizontal, 22)
                    .frame(height: 58)
                    .background(Theme.paper, in: .capsule)
                    .overlay(Capsule().strokeBorder(topicFocused ? Theme.ink : Theme.hairline, lineWidth: topicFocused ? 2 : 1))
                    .animation(.snappy, value: topicFocused)
                    .accessibilityIdentifier("topicField")
                Button { start(topic) } label: {
                    Label("Explore", systemImage: "arrow.right").labelStyle(TrailingIcon()).font(Theme.body(20, weight: .bold)).frame(minHeight: 50)
                }
                .buttonStyle(MachineButtonStyle(kind: .primary))
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("explore")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Readout("or try")
                    ForEach(starters.indices, id: \.self) { i in
                        Button { start(starterText(i)) } label: { Text(starters[i]).font(Theme.body(16, weight: .semibold)) }
                            .buttonStyle(MachineButtonStyle(kind: .quiet))
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 6)
            }
        }
        .padding(28)
        .panel(Theme.card, radius: 32)
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
        Task { if let id = await library.create(title: t) { open = [id] } }
    }
}

/// A notebook as a book cover: its first picture, its title, how much is in it.
struct NotebookCover: View {
    let meta: NotebookMeta
    let cover: UIImage?
    let cardCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.stub
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Rotor(size: 64, color: Theme.ink.opacity(0.14))
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 14))
            .padding([.horizontal, .top], 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(meta.title)
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Readout(text: Text("\(cardCount) cards"), color: Theme.ink)
                    Circle().fill(Theme.hairline).frame(width: 4, height: 4)
                    Readout(text: Text(meta.updatedAt, format: .relative(presentation: .named)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panel(Theme.card, radius: 22)
        .contentShape(.rect(cornerRadius: 22))
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
