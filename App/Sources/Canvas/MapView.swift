import EnjinKit
import SwiftUI

/// "See the whole map": every portal in the notebook as a tree (plan §3.2).
struct MapView: View {
    @Environment(\.dismiss) private var dismiss
    let session: NotebookSession
    let current: String?
    let onSelect: (String) -> Void

    struct Row: Identifiable {
        let id: String
        let title: String
        let cardCount: Int
        let depth: Int
    }

    /// Depth-first, always fully expanded: the point is to see everything at once.
    private func rows(_ portal: Portal, depth: Int = 0) -> [Row] {
        let cards = session.activeCards(in: portal.portalId)
        // Children follow the order of the cards that own them.
        let children = cards.compactMap { card in session.data.portals.first { $0.ownerCardId == card.id } }
        return [Row(id: portal.portalId, title: portal.title, cardCount: cards.count, depth: depth)]
            + children.flatMap { rows($0, depth: depth + 1) }
    }

    var body: some View {
        NavigationStack {
            List(session.portal(session.rootPortalId).map { rows($0) } ?? []) { row in
                Button { onSelect(row.id) } label: {
                    HStack {
                        Text(row.title).fontWeight(row.id == current ? .bold : .regular)
                        Spacer()
                        Text("\(row.cardCount)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.leading, CGFloat(row.depth) * 24)
                }
                .foregroundStyle(.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.title)
                .accessibilityValue("\(row.cardCount) cards")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("map:\(row.title)")
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct NewCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type: CardType = .topic
    @State private var title = ""
    @State private var summary = ""
    let onCreate: (CardType, String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $type) {
                    Text("Topic").tag(CardType.topic)
                    Text("Note").tag(CardType.note)
                }
                .pickerStyle(.segmented)
                TextField("Title", text: $title)
                TextField("What's it about?", text: $summary, axis: .vertical)
                    .lineLimit(2...5)
            }
            .navigationTitle("New card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onCreate(type, title.trimmingCharacters(in: .whitespaces), summary.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
