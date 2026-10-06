import EnjinKit
import SwiftUI
import UIKit

struct IdentifiedString: Identifiable {
    let id: String
}

/// Everything about one card: its picture, full text, where it came from, and
/// (for the kid's own cards) editing. Rich content lives here, not on the canvas.
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

    /// The kid edits their own cards; Enjin's cards are read-only (they can ask about them instead).
    private var editable: Bool { card.createdBy == .kid }

    private var changed: Bool {
        title != card.title || summary != card.summary || bodyText != (card.body ?? "")
    }

    var body: some View {
        EnjinSheet(title: card.type == .note ? "Note" : "Card") {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let picture {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(uiImage: picture)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 360)
                                .clipShape(.rect(cornerRadius: 14))
                                .sticker(Theme.card, radius: 14)
                                .accessibilityLabel(Text("Picture for \(card.title)"))
                            HStack(spacing: 10) {
                                if card.image?.kind == .illustration {
                                    Label("Illustration made on this iPad (not a real photo)", systemImage: "paintbrush")
                                } else if let credit = card.image?.credit {
                                    Label { Text("Picture: \(credit)") } icon: { Image(systemName: "camera") }
                                }
                                if card.image?.kind != .illustration, let url = card.image?.sourceURL.flatMap(URL.init(string:)) {
                                    Link("About this picture", destination: url).fontWeight(.semibold)
                                }
                            }
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.inkSoft)
                        }
                    }

                    if editable {
                        TextField(text: $title) { Text("Title") }.font(Theme.display(30)).enjinField()
                        TextField(text: $summary, axis: .vertical) { Text("Summary") }.lineLimit(2...4).enjinField()
                        TextField(text: $bodyText, axis: .vertical) { Text("Anything else…") }.lineLimit(3...10).enjinField()
                    } else {
                        Text(card.title).font(Theme.display(36)).foregroundStyle(Theme.ink)
                        Text(card.summary).font(Theme.body(20)).foregroundStyle(Theme.ink)
                        if let body = card.body, !body.isEmpty {
                            Text(body).font(Theme.body(18)).foregroundStyle(Theme.inkSoft)
                        }
                    }

                    if let sources = card.sources, !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HandHeading(text: "Sources", size: 22)
                            ForEach(sources, id: \.url) { s in
                                if let url = URL(string: s.url) {
                                    Link(destination: url) {
                                        Label(s.title, systemImage: "link").font(Theme.body(16, weight: .semibold)).lineLimit(1)
                                    }
                                    .buttonStyle(StickerButtonStyle(kind: .quiet))
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: card.createdBy == .kid ? "person.fill" : "sparkle").foregroundStyle(Theme.ember)
                        Text(card.createdBy == .kid ? "Made by you" : "Made by Enjin")
                        Text(verbatim: "·")
                        Text(card.createdAt, format: .dateTime.day().month().hour().minute())
                    }
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)

                    if card.state == .stub {
                        Text("Not explored yet. Dive in to fill it.").font(Theme.body(16)).foregroundStyle(Theme.inkSoft)
                    }

                    HStack(spacing: 12) {
                        if let onDive {
                            Button(action: onDive) { Label("Dive in", systemImage: "arrow.down.right") }
                                .buttonStyle(StickerButtonStyle(kind: .primary))
                        }
                        if editable {
                            Button {
                                let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                                let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                                onSave(t, summary.trimmingCharacters(in: .whitespacesAndNewlines), b.isEmpty ? nil : b)
                                dismiss()
                            } label: { Label("Save", systemImage: "checkmark") }
                                .buttonStyle(StickerButtonStyle(kind: onDive == nil ? .primary : .plain))
                                .disabled(!changed || title.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(24)
            }
        }
        .task {
            if let image = card.image, let loadImage { picture = await loadImage(image) }
        }
    }
}
