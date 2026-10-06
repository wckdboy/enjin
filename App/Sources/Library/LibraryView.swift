import EnjinKit
import SwiftUI

struct LibraryView: View {
    @State private var library: Library
    @State private var open: [String] = []
    @State private var newTitle = ""
    @State private var askingTitle = false

    init(store: NotebookStore) {
        _library = State(initialValue: Library(store: store))
    }

    var body: some View {
        NavigationStack(path: $open) {
            List {
                ForEach(library.notebooks) { nb in
                    NavigationLink(value: nb.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nb.title).font(.title3.weight(.semibold))
                            Text(nb.updatedAt, format: .relative(presentation: .named)).font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { library.notebooks[$0].id }
                    Task { for id in ids { await library.delete(id) } }
                }
            }
            .overlay {
                if library.notebooks.isEmpty {
                    ContentUnavailableView("No notebooks yet", systemImage: "square.on.square.dashed",
                                           description: Text("What do you want to explore?"))
                }
            }
            .navigationTitle("Enjin")
            .toolbar {
                Button { askingTitle = true } label: { Label("New notebook", systemImage: "plus") }
            }
            .alert("What do you want to explore?", isPresented: $askingTitle) {
                TextField("e.g. Roman Empire", text: $newTitle)
                Button("Create") {
                    let title = newTitle
                    newTitle = ""
                    Task { if let id = await library.create(title: title) { open = [id] } }
                }
                Button("Cancel", role: .cancel) { newTitle = "" }
            }
            .navigationDestination(for: String.self) { id in
                NotebookScreen(notebookId: id, store: library.store)
                    .onDisappear { Task { await library.refresh() } }
            }
            .task { await library.load() }
        }
    }
}

/// Opens a notebook from disk, then shows its canvas.
struct NotebookScreen: View {
    let notebookId: String
    let store: NotebookStore
    @State private var controller: CanvasController?
    @State private var error: String?

    var body: some View {
        Group {
            if let controller {
                CanvasScreen(controller: controller)
            } else if let error {
                ContentUnavailableView("Couldn't open notebook", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            do {
                controller = CanvasController(session: try await NotebookSession.open(notebookId, store: store))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
