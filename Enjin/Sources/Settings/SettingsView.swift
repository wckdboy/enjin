import EnjinKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppSettings
    let telemetry: Telemetry
    @State private var keyDraft = ""
    @State private var showConsent = false
    @State private var spentToday = 0.0
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Enjin uses", selection: $settings.provider) {
                        ForEach(AppSettings.Provider.allCases) { Text($0.label).tag($0) }
                    }
                    Text(settings.activeDescription).font(.callout).foregroundStyle(.secondary)
                } header: {
                    Text("Enjin's brain")
                }

                Section {
                    if !settings.consentGiven {
                        Button("Set up a Claude key…") { showConsent = true }
                    } else if settings.hasKey {
                        LabeledContent("API key", value: "Saved on this iPad")
                        Picker("Model", selection: $settings.modelId) {
                            ForEach(AnthropicModel.all) { Text($0.label).tag($0.id) }
                        }
                        TextField("Workspace ID (only if needed, wrkspc_...)", text: $settings.workspaceId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.callout.monospaced())
                        Button {
                            Task {
                                testing = true
                                let err = await settings.testConnection()
                                testResult = err.map { (false, $0) } ?? (true, "Connected. Enjin is ready.")
                                testing = false
                            }
                        } label: {
                            HStack {
                                Text("Test connection")
                                if testing { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(testing)
                        if let r = testResult {
                            Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(r.ok ? .green : .red)
                                .font(.callout)
                            if !r.ok && r.message.localizedCaseInsensitiveContains("workspace") {
                                Text("This key belongs to an organization but doesn't pick a workspace. Paste a workspace ID from the Claude Console (it starts with wrkspc_), or create a new key inside a workspace.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Remove key", role: .destructive) { settings.removeKey(); testResult = nil }
                    } else {
                        SecureField("sk-ant-…", text: $keyDraft)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Save key") {
                            settings.saveKey(keyDraft)
                            keyDraft = ""
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("For parents: Claude API key")
                } footer: {
                    Text("The key is stored in this iPad's Keychain and never leaves it except to talk to Anthropic.")
                }

                Section {
                    Toggle("Show pictures on cards", isOn: $settings.showPictures)
                } header: {
                    Text("Pictures")
                } footer: {
                    Text("Facts get real pictures from Wikipedia (free-licensed, credited; a word filter skips unsuitable ones, but no filter is perfect). Ideas get illustrations made on this iPad with Image Playground, where available. Everything gets Enjin's sketchbook look.")
                }

                Section {
                    Toggle("Prepare cards ahead", isOn: $settings.prepareAhead)
                } footer: {
                    Text("Fills unexplored cards in the background while your kid looks at them, so diving in is instant. Uses noticeably more of the daily limit.")
                }

                Section {
                    Stepper(value: $settings.dailyCapUSD, in: 0.5...20, step: 0.5) {
                        LabeledContent("Daily limit", value: settings.dailyCapUSD.formatted(.currency(code: "USD")))
                    }
                    LabeledContent("Spent today", value: spentToday.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                } header: {
                    Text("Spending")
                } footer: {
                    Text("When the limit is reached, Enjin rests until tomorrow.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task { spentToday = await telemetry.spentToday() }
            .sheet(isPresented: $showConsent) {
                ParentConsentView { settings.consentGiven = true }
            }
        }
    }
}

/// Plan §7: a parent sees what goes where and what it costs before any key is used.
struct ParentConsentView: View {
    @Environment(\.dismiss) private var dismiss
    let onAgree: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before you add a key").font(.title.bold())
                    Label("When your kid asks Enjin something, what they typed and a short description of their canvas (card titles and summaries, counts of their drawings, and any text notes) are sent to Anthropic to generate an answer.", systemImage: "arrow.up.message")
                    Label("Enjin searches the web to back up facts. Adult and gambling sites are blocked, but no filter is perfect.", systemImage: "globe")
                    Label("Using the key costs money on your Anthropic account. You set a daily limit; when it's reached, Enjin stops until tomorrow.", systemImage: "creditcard")
                    Label("Nothing is shared with anyone else. Notebooks and usage logs stay on this iPad.", systemImage: "lock.ipad")
                    Text("Enjin is an AI. It can be wrong; it shows its sources so you can check.").foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("I agree") {
                        onAgree()
                        dismiss()
                    }
                }
            }
        }
    }
}
