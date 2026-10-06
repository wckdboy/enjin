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

    private let starters: [LocalizedStringKey] = ["Volcanoes", "Ancient Egypt", "Black holes", "Dinosaurs", "The Vikings", "The human brain"]

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
                            HandHeading(text: "Your notebooks", size: 30)
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
            .background(Theme.paper.ignoresSafeArea())
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
            HandHeading(text: "What do you want to explore?", size: 40)
            HStack(spacing: 12) {
                TextField(text: $topic) { Text("A topic, a question, anything…") }
                    .font(Theme.body(22))
                    .foregroundStyle(Theme.ink)
                    .focused($topicFocused)
                    .submitLabel(.go)
                    .onSubmit { start(topic) }
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .sticker(.white, radius: Theme.radius, lifted: false)
                    .accessibilityIdentifier("topicField")
                Button { start(topic) } label: {
                    Label("Explore", systemImage: "bolt.fill").font(Theme.body(20, weight: .bold)).frame(minHeight: 50)
                }
                .buttonStyle(StickerButtonStyle(kind: .primary))
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("explore")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text("or try").font(Theme.body(16)).foregroundStyle(Theme.inkSoft)
                    ForEach(starters.indices, id: \.self) { i in
                        Button { start(starterText(i)) } label: { Text(starters[i]).font(Theme.body(16, weight: .semibold)) }
                            .buttonStyle(StickerButtonStyle(kind: .quiet, radius: 22))
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 6)
            }
        }
        .padding(28)
        .sticker(Theme.card, radius: 24)
    }

    /// The starter's text in the current language (the key itself is English).
    private func starterText(_ i: Int) -> String {
        let keys = ["Volcanoes", "Ancient Egypt", "Black holes", "Dinosaurs", "The Vikings", "The human brain"]
        return keys[i].localizedIn(settings.language)
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
                Theme.accentSoft
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Image("MotorMark").renderingMode(.template).resizable().scaledToFit().frame(height: 70).foregroundStyle(Theme.ink.opacity(0.18))
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: Theme.line) }

            VStack(alignment: .leading, spacing: 6) {
                Text(meta.title)
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("\(cardCount) cards")
                    Text(verbatim: "·")
                    Text(meta.updatedAt, format: .relative(presentation: .named))
                }
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(.rect(cornerRadius: 20))
        .sticker(Theme.card, radius: 20)
        .contentShape(.rect(cornerRadius: 20))
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
