import EnjinKit
import SwiftUI

/// The kid's line to Enjin: ask, see what it's doing, stop, undo.
struct AgentDock: View {
    let agent: AgentSession
    let onAsk: (String) -> Void
    let onGoToSuggestion: () -> Void
    let onNextStep: (AgentSession.NextStep) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let s = agent.suggestion, let card = agent.session.card(s.cardId) {
                Button(action: onGoToSuggestion) {
                    Label("\(s.reason) — go to “\(card.title)”", systemImage: "arrow.forward.circle.fill")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .transition(.opacity)
            }

            if !agent.nextSteps.isEmpty && !agent.isRunning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(agent.nextSteps) { step in
                            Button { onNextStep(step) } label: {
                                switch step {
                                case .dive(_, let title): Label(title, systemImage: "arrow.down.right.circle.fill")
                                case .ask(let q): Text(q)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(step.isDive ? .blue : .orange)
                            .lineLimit(1)
                        }
                    }
                }
                .transition(.opacity)
            }

            if let line = statusLine {
                HStack(alignment: .top, spacing: 8) {
                    if agent.isRunning && agent.prefetchingCardId == nil { ProgressView().controlSize(.small) }
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(isError ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                    if isError {
                        Button("OK") { agent.dismissError() }.font(.callout)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 14))
            }

            HStack(spacing: 8) {
                TextField("Ask Enjin anything…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    // Multi-line fields insert a newline on Return; kids expect Return to send.
                    .onChange(of: text) { _, new in
                        if new.hasSuffix("\n") {
                            text = String(new.dropLast())
                            send()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.background, in: .capsule)
                    .overlay(Capsule().strokeBorder(.quaternary))
                if agent.isRunning && agent.prefetchingCardId == nil {
                    Button { agent.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                        .accessibilityLabel("Stop")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send")
                }
                if agent.canUndo && !agent.isRunning {
                    Button { Task { await agent.undoLastTurn() } } label: { Image(systemName: "arrow.uturn.backward.circle").font(.title) }
                        .accessibilityLabel("Undo Enjin's last change")
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .animation(.snappy, value: agent.status)
        .animation(.snappy, value: agent.suggestion)
        .animation(.snappy, value: agent.nextSteps)
    }

    private var isError: Bool {
        if case .failed = agent.status { true } else { false }
    }

    private var statusLine: String? {
        switch agent.status {
        case .failed(let message): return message
        case .working(.thinking): return agent.reply.isEmpty ? "Thinking…" : agent.reply
        case .working(.searching(let q)): return q.isEmpty ? "Looking things up…" : "Looking up “\(q)”…"
        case .working(.writing): return agent.reply.isEmpty ? "Making cards…" : agent.reply
        case .idle: return agent.reply.isEmpty ? nil : agent.reply
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""
        focused = false // put the keyboard away so the kid sees the cards arrive
        onAsk(t)
    }
}

extension AgentSession.NextStep {
    var isDive: Bool { if case .dive = self { true } else { false } }
}
