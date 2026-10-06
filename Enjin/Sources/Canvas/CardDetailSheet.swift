import EnjinKit
import SwiftUI
import UIKit

struct IdentifiedString: Identifiable {
    let id: String
}

/// Everything about one card: full text, where it came from, and (for the
/// kid's own cards) editing. Rich content lives here, not on the canvas.
struct CardDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: StoredCard
    let onSave: (String, String, String?) -> Void
    let onDive: (() -> Void)?
    var loadImage: ((CardImage) async -> UIImage?)?
    @State private var picture: UIImage?

    @State private var title: String
    @State private var summary: String
    @State private var bodyText: String

    init(card: StoredCard, onSave: @escaping (String, String, String?) -> Void, onDive: (() -> Void)?,
         loadImage: ((CardImage) async -> UIImage?)? = nil) {
        self.card = card
        self.onSave = onSave
        self.onDive = onDive
        self.loadImage = loadImage
        _title = State(initialValue: card.title)
        _summary = State(initialValue: card.summary)
        _bodyText = State(initialValue: card.body ?? "")
    }

    /// The kid edits their own cards; agent cards are read-only (they can ask about them instead).
    private var editable: Bool { card.createdBy == .kid }

    private var changed: Bool {
        title != card.title || summary != card.summary || bodyText != (card.body ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let picture {
                    Section {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityLabel("Picture for \(card.title)")
                        if card.image?.kind == .illustration {
                            Text("Illustration made on this iPad (not a real photo)").font(.caption).foregroundStyle(.secondary)
                        } else if let credit = card.image?.credit {
                            Text("Picture: \(credit)").font(.caption).foregroundStyle(.secondary)
                        }
                        if card.image?.kind != .illustration, let url = card.image?.sourceURL.flatMap(URL.init(string:)) {
                            Link("About this picture", destination: url).font(.caption)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if editable {
                    TextField("Title", text: $title)
                        .font(.title2.weight(.semibold))
                    TextField("Summary", text: $summary, axis: .vertical).lineLimit(2...4)
                    Section("Notes") {
                        TextField("Anything else…", text: $bodyText, axis: .vertical).lineLimit(4...12)
                    }
                } else {
                    Section {
                        Text(card.title).font(.title2.weight(.semibold))
                        Text(card.summary)
                        if let body = card.body, !body.isEmpty { Text(body) }
                    }
                }
                if let sources = card.sources, !sources.isEmpty {
                    Section("Sources") {
                        ForEach(sources, id: \.url) { s in
                            if let url = URL(string: s.url) { Link(s.title, destination: url) } else { Text(s.title) }
                        }
                    }
                }
                Section("Where this came from") {
                    LabeledContent("Made by", value: card.createdBy == .kid ? "You" : "Enjin")
                    LabeledContent("Created", value: card.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if card.state == .stub {
                        Text("Not explored yet — dive in to fill it.").foregroundStyle(.secondary)
                    }
                }
                if let onDive {
                    Section {
                        Button("Dive in", systemImage: "arrow.down.right.circle", action: onDive)
                    }
                }
            }
            .task {
                if let image = card.image, let loadImage { picture = await loadImage(image) }
            }
            .navigationTitle(card.type == .note ? "Note" : "Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(editable ? "Cancel" : "Close") { dismiss() } }
                if editable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(t, summary.trimmingCharacters(in: .whitespacesAndNewlines), b.isEmpty ? nil : b)
                            dismiss()
                        }
                        .disabled(!changed || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
