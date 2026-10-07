import EnjinKit
import SwiftUI
import UIKit

/// Where to open: a world, and optionally a place inside it.
struct Route: Hashable {
    let notebookId: String
    var portalId: String?
}

/// Home: start a new world, jump back into the last one, and keep your worlds and your own notes in order.
/// Worlds are round portals, the same doors you zoom through inside them.
struct LibraryView: View {
    @State private var library: Library
    let settings: AppSettings
    let telemetry: Telemetry
    @State private var open: [Route] = []
    @State private var topic = ""
    /// How deep new notebooks go; remembered between launches.
    @AppStorage("explore.level") private var level: ExplorerLevel = .student
    /// Shelves made before anything was put on them.
    @AppStorage("home.extraShelves") private var extraShelvesRaw = ""
    @State private var showSettings = false
    @State private var confirmDelete: NotebookMeta?
    @State private var shelf: Shelf = .all
    @State private var query = ""
    @State private var renaming: NotebookMeta?
    @State private var newName = ""
    @State private var makingShelfFor: NotebookMeta??
    @State private var dropTarget: String?
    @FocusState private var topicFocused: Bool

    enum Shelf: Hashable { case all, pinned, named(String) }

    init(store: NotebookStore, settings: AppSettings, telemetry: Telemetry) {
        _library = State(initialValue: Library(store: store))
        self.settings = settings
        self.telemetry = telemetry
    }

    /// Starter topics (English keys; shown and started in the current language).
    private static let starterKeys = ["How AI learns", "Robots", "Black holes", "CRISPR", "How a CPU works", "Electric motors",
                                      "The human brain", "Quantum computers"]
    private var starters: [LocalizedStringKey] { Self.starterKeys.map { LocalizedStringKey($0) } }

    private var extraShelves: [String] { extraShelvesRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
    private var shelves: [String] { Array(Set(library.collections + extraShelves)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

    /// The worlds on the chosen shelf, matching the search: pinned first, then most recently visited.
    private var shown: [NotebookMeta] {
        let hits = library.matches(query).worlds
        return library.notebooks.filter { nb in
            guard hits.contains(nb.id) else { return false }
            switch shelf {
            case .all: return true
            case .pinned: return nb.pinned == true
            case .named(let name): return nb.collection == name
            }
        }.sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            return ($0.openedAt ?? $0.updatedAt) > ($1.openedAt ?? $1.updatedAt)
        }
    }

    var body: some View {
        NavigationStack(path: $open) {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    homeBar
                    if query.isEmpty {
                        explorePrompt
                        if let latest = library.latest { jumpBackIn(latest) }
                    }
                    worlds
                    notesShelf
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FieldBackground(depth: true).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                NotebookScreen(notebookId: route.notebookId, portalId: route.portalId, store: library.store, settings: settings, telemetry: telemetry)
                    .onDisappear { Task { await library.refresh() } }
            }
            .sheet(isPresented: $showSettings) { SettingsView(settings: settings, telemetry: telemetry) }
            .confirmationDialog(Text("Delete this notebook?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible, presenting: confirmDelete) { nb in
                Button("Delete “\(nb.title)”", role: .destructive) { Task { await library.delete(nb.id) } }
            } message: { _ in
                Text("All its cards, drawings and pictures will be gone.")
            }
            .alert("Rename world", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { if let nb = renaming { Task { await library.rename(nb.id, to: newName) } } }
            }
            .alert("New shelf", isPresented: Binding(get: { makingShelfFor != nil }, set: { if !$0 { makingShelfFor = nil } })) {
                TextField("Name, like Physics or School project", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Make it") { makeShelf(newName, putting: makingShelfFor ?? nil) }
            }
            .task {
                await library.load(language: settings.language)
                #if DEBUG
                // Screenshots/previews: jump straight into the first notebook.
                if ProcessInfo.processInfo.arguments.contains("-openFirstNotebook"), let first = library.notebooks.first { open = [Route(notebookId: first.id)] }
                #endif
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - Sections

    private var homeBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Wordmark(size: 34)
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.fgSoft)
                TextField(text: $query) { Text("Search your worlds and notes").foregroundStyle(Theme.fgFaint) }
                    .font(Theme.body(17))
                    .submitLabel(.search)
                    .accessibilityIdentifier("homeSearch")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.fgFaint) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, 18)
            .frame(width: 340, height: 46)
            .wellCapsule()
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(RotorKeyStyle())
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("settings")
        }
    }

    /// The world you were last in, as a big portal: straight back to where you were.
    private func jumpBackIn(_ nb: NotebookMeta) -> some View {
        Button { open = [Route(notebookId: nb.id, portalId: nb.lastPortalId)] } label: {
            HStack(alignment: .center, spacing: 34) {
                PortalCover(meta: nb, cover: library.covers[nb.id], size: 190, levels: library.depths[nb.id] ?? 1)
                VStack(alignment: .leading, spacing: 12) {
                    Readout("Jump back in")
                    Text(nb.title).font(Theme.display(38)).tracking(-0.8).foregroundStyle(Theme.fg).lineLimit(2).multilineTextAlignment(.leading)
                    if let place = library.lastPlace[nb.id] {
                        Label { Text("You were in \(place)") } icon: { Image(systemName: "arrow.turn.down.right") }
                            .font(Theme.body(17)).foregroundStyle(Theme.fgSoft)
                    }
                    WorldStats(meta: nb, cards: library.counts[nb.id] ?? 0, levels: library.depths[nb.id] ?? 1,
                               notes: library.notes.filter { $0.notebookId == nb.id }.count)
                    Label("Continue", systemImage: "arrow.right").labelStyle(TrailingIcon())
                        .font(Theme.body(17, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.fg))
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(30)
        }
        .buttonStyle(CoverPressStyle())
        .accessibilityIdentifier("jumpBackIn")
    }

    /// Shelves to file worlds on, and the worlds themselves.
    private var worlds: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(title: query.isEmpty ? "Your worlds" : "Found") {
                Readout(text: Text("\(library.notebooks.count) worlds"))
            }
            if library.notebooks.isEmpty {
                emptyShelf
            } else {
                shelfChips
                let list = shown
                if list.isEmpty {
                    Text(query.isEmpty ? "Nothing on this shelf yet. Drag a world onto it, or long-press a world and choose a shelf." : "No worlds match.")
                        .font(Theme.body(16)).foregroundStyle(Theme.fgSoft)
                        .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 28)], alignment: .leading, spacing: 34) {
                        ForEach(list) { nb in world(nb) }
                    }
                }
            }
        }
    }

    private func world(_ nb: NotebookMeta) -> some View {
        NavigationLink(value: Route(notebookId: nb.id)) {
            VStack(spacing: 14) {
                PortalCover(meta: nb, cover: library.covers[nb.id], size: 168, levels: library.depths[nb.id] ?? 1)
                VStack(spacing: 6) {
                    Text(nb.title).font(Theme.display(21)).tracking(-0.3).foregroundStyle(Theme.fg)
                        .lineLimit(2).multilineTextAlignment(.center)
                    WorldStats(meta: nb, cards: library.counts[nb.id] ?? 0, levels: library.depths[nb.id] ?? 1, notes: nil, compact: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(.rect)
        }
        .buttonStyle(PortalPressStyle())
        .draggable(nb.id)
        .contextMenu {
            Button { Task { await library.setPinned(nb.id, nb.pinned != true) } } label: {
                Label(nb.pinned == true ? "Unpin" : "Pin to the front", systemImage: nb.pinned == true ? "pin.slash" : "pin")
            }
            // Flat, not a submenu: one press to file a world.
            Section {
                ForEach(shelves.filter { $0 != nb.collection }, id: \.self) { name in
                    Button { Task { await library.move(nb.id, to: name) } } label: { Label("Move to \(name)", systemImage: "books.vertical") }
                }
                Button { newName = ""; makingShelfFor = .some(nb) } label: { Label("New shelf…", systemImage: "plus") }
                if nb.collection != nil {
                    Button { Task { await library.move(nb.id, to: nil) } } label: { Label("Take off the shelf", systemImage: "tray.and.arrow.up") }
                }
            }
            Button { newName = nb.title; renaming = nb } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete = nb } label: { Label("Delete notebook", systemImage: "trash") }
        }
        .accessibilityIdentifier("notebook:\(nb.title)")
    }

    /// All, Pinned, your shelves, and a new one. Drop a world on a shelf to file it there.
    private var shelfChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("All", count: library.notebooks.count, selected: shelf == .all) { shelf = .all }
                let pinned = library.notebooks.filter { $0.pinned == true }.count
                if pinned > 0 { chip("Pinned", icon: "pin.fill", count: pinned, selected: shelf == .pinned) { shelf = .pinned } }
                ForEach(shelves, id: \.self) { name in
                    chip(LocalizedStringKey(name), icon: "books.vertical", count: library.notebooks.filter { $0.collection == name }.count,
                         selected: shelf == .named(name), dropping: dropTarget == name) { shelf = .named(name) }
                        .dropDestination(for: String.self) { ids, _ in
                            for id in ids { Task { await library.move(id, to: name) } }
                            return !ids.isEmpty
                        } isTargeted: { dropTarget = $0 ? name : (dropTarget == name ? nil : dropTarget) }
                        .contextMenu {
                            Button(role: .destructive) {
                                for nb in library.notebooks where nb.collection == name { Task { await library.move(nb.id, to: nil) } }
                                extraShelvesRaw = extraShelves.filter { $0 != name }.joined(separator: "\n")
                                if shelf == .named(name) { shelf = .all }
                            } label: { Label("Remove shelf (the worlds stay)", systemImage: "trash") }
                        }
                }
                Button { newName = ""; makingShelfFor = .some(nil) } label: { Label("New shelf", systemImage: "plus") }
                    .buttonStyle(KeyButtonStyle(kind: .quiet, size: .small))
                    .accessibilityIdentifier("newShelf")
            }
            .padding(.vertical, 6)
        }
    }

    private func chip(_ title: LocalizedStringKey, icon: String? = nil, count: Int, selected: Bool, dropping: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title)
                Text(verbatim: "\(count)").font(Theme.mono(13)).opacity(0.6)
            }
            .font(Theme.body(16, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(selected ? .white : Theme.fg)
            .background(Capsule().fill(selected ? Theme.fg : Theme.deck))
            .overlay(Capsule().strokeBorder(dropping ? Theme.fg : Theme.edge, lineWidth: dropping ? 2 : 1))
            .scaleEffect(dropping ? 1.08 : 1)
            .animation(.snappy, value: dropping)
        }
        .buttonStyle(.plain)
    }

    /// Everything you made yourself, across all your worlds: tap to land right where it lives.
    @ViewBuilder private var notesShelf: some View {
        let notes = library.matches(query).notes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Your notes") { Readout(text: Text("\(notes.count) notes")) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(notes.prefix(40)) { note in
                            Button { open = [Route(notebookId: note.notebookId, portalId: note.portalId)] } label: { NoteTile(note: note) }
                                .buttonStyle(CoverPressStyle())
                                .accessibilityIdentifier("note:\(note.title)")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func makeShelf(_ name: String, putting nb: NotebookMeta?) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if !shelves.contains(n) { extraShelvesRaw = (extraShelves + [n]).joined(separator: "\n") }
        if let nb { Task { await library.move(nb.id, to: n) } }
        shelf = .named(n)
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
        // A new world goes on the shelf you're looking at.
        let collection: String? = if case .named(let name) = shelf { name } else { nil }
        Task { if let id = await library.create(title: t, level: level, collection: collection) { open = [Route(notebookId: id)] } }
    }
}

/// A world as a round portal (the same doors you zoom through inside it): its cover art behind
/// glass, in an ink ring; its initial while it has no picture yet.
struct PortalCover: View {
    let meta: NotebookMeta
    let cover: UIImage?
    var size: CGFloat = 168
    /// Levels explored: drawn as the world's little orbit while it has no picture.
    var levels: Int = 1

    var body: some View {
        ZStack {
            Circle().fill(Theme.deck)
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                // The world inside: its initial, with an orbit of the places you've explored.
                Canvas { g, sz in
                    let c = CGPoint(x: sz.width / 2, y: sz.height / 2), r = sz.width * 0.33
                    g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.42, width: 2 * r, height: 2 * r * 0.42)),
                             with: .color(Theme.fg.opacity(0.18)), lineWidth: 1.2)
                    let n = max(1, min(12, levels))
                    for i in 0..<n {
                        let a = Double(i) / Double(n) * 2 * .pi + 0.6
                        let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.42)
                        let d = sz.width * (i == 0 ? 0.05 : 0.035)
                        g.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(Theme.fg.opacity(i == 0 ? 0.8 : 0.45)))
                    }
                }
                Text(String(meta.title.prefix(1)).uppercased())
                    .font(Theme.display(size * 0.34))
                    .foregroundStyle(Theme.fg.opacity(0.2))
            }
            // Glass: a soft highlight across the top.
            Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .center))
                .blendMode(.screen)
            Circle().strokeBorder(Theme.fg, lineWidth: max(4, size * 0.035))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.14), radius: size * 0.09, y: size * 0.06)
        .overlay(alignment: .topTrailing) {
            if meta.pinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Circle().fill(Theme.fg))
                    .offset(x: -size * 0.04, y: size * 0.04)
            }
        }
    }
}

/// How big a world is, and how recently you were there.
struct WorldStats: View {
    let meta: NotebookMeta
    let cards: Int
    let levels: Int
    let notes: Int?
    var compact = false

    var body: some View {
        let parts: [Text] = [
            meta.level.map { Text($0.label) },
            Text("\(cards) cards"),
            compact ? nil : Text("\(levels) levels deep"),
            notes.flatMap { $0 > 0 ? Text("\($0) of your notes") : nil },
            Text(meta.openedAt ?? meta.updatedAt, format: .relative(presentation: .named)),
        ].compactMap { $0 }
        HStack(spacing: 8) {
            ForEach(parts.indices, id: \.self) { i in
                if i > 0 { Text(verbatim: "·").foregroundStyle(Theme.fgFaint) }
                Readout(text: parts[i], color: i == parts.count - 1 ? Theme.fgSoft : Theme.fg)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// One of your notes or drawings, with where it lives.
struct NoteTile: View {
    let note: ExplorerNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Theme.deck
                if let thumb = note.thumbnail {
                    Image(uiImage: thumb).resizable().scaledToFit().blendMode(.multiply).padding(10)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).font(Theme.title(19)).foregroundStyle(Theme.fg).lineLimit(2)
                        if !note.summary.isEmpty { Text(note.summary).font(Theme.body(14)).foregroundStyle(Theme.fgSoft).lineLimit(3) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
                }
            }
            .frame(width: 220, height: 132)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Label { Text(note.sketch ? "Drawing" : "Note") } icon: { Image(systemName: note.sketch ? "pencil.and.scribble" : "note.text") }
                    .font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.fg)
                Text(note.portalTitle == note.notebookTitle ? note.notebookTitle : "\(note.portalTitle) · \(note.notebookTitle)")
                    .font(Theme.body(13)).foregroundStyle(Theme.fgSoft).lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)
        }
        .padding(12)
    }
}

/// Portals press like glass: they dip.
struct PortalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.35), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: configuration.isPressed) { _, now in now }
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
    /// A place inside it to open at (jump back in, a note), or its top level.
    var portalId: String? = nil
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
                let c = CanvasController(session: try await NotebookSession.open(notebookId, store: store),
                                         settings: settings, telemetry: telemetry)
                c.startPortalId = portalId
                controller = c
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
