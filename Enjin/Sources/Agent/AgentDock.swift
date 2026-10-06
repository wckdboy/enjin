import EnjinKit
import SwiftUI

/// The kid's line to Enjin: ask, see what it's doing, stop, undo.
struct AgentDock: View {
    let agent: AgentSession
    let onAsk: (String) -> Void
    let onGoToSuggestion: () -> Void
    let onNextStep: (AgentSession.NextStep) -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.language.languageCode?.identifier == "da" ? .da : .en }
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = agent.suggestion, let card = agent.session.card(s.cardId) {
                Button(action: onGoToSuggestion) {
                    Label { Text(verbatim: "\(s.reason) → \(card.title)") } icon: { Image(systemName: "eye") }
                        .lineLimit(1)
                }
                .buttonStyle(KeyButtonStyle(kind: .secondary, size: .small))
                .transition(.opacity)
            }

            if !agent.nextSteps.isEmpty && !agent.isRunning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(agent.nextSteps) { step in
                            Button { onNextStep(step) } label: {
                                switch step {
                                case .dive(_, let title):
                                    Label { Text(title) } icon: { Image(systemName: "arrow.down.right") }
                                case .ask(let q):
                                    Text(q)
                                }
                            }
                            .buttonStyle(KeyButtonStyle(kind: step.isDive ? .primary : .secondary, size: .small))
                            .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 6)
                    .padding(.trailing, 6)
                }
                .transition(.opacity)
            }

            if let line = statusLine {
                HStack(alignment: .top, spacing: 10) {
                    if !isError {
                        Activity(size: 18, working: agent.isRunning && agent.prefetchingCardId == nil).padding(.top, 2)
                    }
                    Text(line)
                        .font(Theme.body(17))
                        .foregroundStyle(isError ? Theme.danger : Theme.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                    if isError {
                        Button("OK") { agent.dismissError() }.buttonStyle(KeyButtonStyle(kind: .primary, size: .small))
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 10) {
                TextField(text: $text, axis: .vertical) { Text("Ask Enjin anything…") }
                    .font(Theme.body(19))
                    .foregroundStyle(Theme.ink)
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .tint(Theme.signal)
                    .well(radius: 24, focused: focused)
                    .accessibilityIdentifier("askField")
                if agent.isRunning && agent.prefetchingCardId == nil {
                    Button { agent.cancel() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(RotorKeyStyle(size: 48))
                        .accessibilityLabel(Text("Stop"))
                } else {
                    Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 20, weight: .heavy)) }
                        .buttonStyle(RotorKeyStyle(active: true, size: 48))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(Text("Send"))
                        .accessibilityIdentifier("send")
                }
                if agent.canUndo && !agent.isRunning {
                    Button { Task { await agent.undoLastTurn() } } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(RotorKeyStyle(size: 48))
                        .accessibilityLabel(Text("Undo Enjin's last change"))
                        .accessibilityIdentifier("undoAgent")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 640)
        .chrome(radius: 34)
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
        case .working(.thinking): return agent.reply.isEmpty ? "Thinking…".localizedIn(language) : agent.reply
        case .working(.searching(let q)):
            return q.isEmpty ? "Looking things up…".localizedIn(language) : String(format: "Looking up “%@”…".localizedIn(language), q)
        case .working(.writing): return agent.reply.isEmpty ? "Making cards…".localizedIn(language) : agent.reply
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
