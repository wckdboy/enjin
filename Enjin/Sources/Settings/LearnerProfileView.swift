import EnjinKit
import SwiftUI

/// User.md, as the explorer sees it: what Enjin has learned about how they learn.
/// They can change anything or start over; Enjin reads it every turn.
struct LearnerProfileView: View {
    let profile: LearnerProfile
    @State private var draft = ""
    @State private var confirmReset = false

    var body: some View {
        EnjinSheet(title: "What Enjin knows about you", cancel: "Cancel", confirm: "Save", onConfirm: { profile.replace(with: draft) }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enjin writes down what it learns about how you learn best: which visuals click, your pace, what you're curious about. Only learning, never anything personal. Change anything you like.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.fgSoft)
                TextEditor(text: $draft)
                    .font(.system(size: 15, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .well(radius: 18)
                    .accessibilityIdentifier("learnerMarkdown")
                HStack {
                    Spacer()
                    Button("Start over", role: .destructive) { confirmReset = true }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, size: .small))
                }
            }
            .padding(24)
        }
        .onAppear { draft = profile.markdown }
        .confirmationDialog("Forget everything Enjin learned about how you learn?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Forget it all", role: .destructive) {
                profile.reset()
                draft = profile.markdown
            }
        }
    }
}
