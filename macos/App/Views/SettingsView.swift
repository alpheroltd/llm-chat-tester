import SwiftUI
import TesterCore

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @ObservedObject var updater: Updater
    @State private var automaticallyChecks = true
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?

    var body: some View {
        @Bindable var app = app
        Form {
            Section("Ollama") {
                TextField("Server URL", text: $app.ollamaURLText)
                Text("Default: http://localhost:11434. Change this only if Ollama runs elsewhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Claude Code CLI path", text: $app.claudePathOverride, prompt: Text("auto-detect"))
                HStack {
                    StatusBadge(status: app.claudeStatus)
                    Spacer()
                    Button("Check again") { Task { await app.refreshClaude() } }
                }
                SecureField("Anthropic API key (optional)", text: $apiKeyDraft, prompt: Text(app.hasAPIKey ? "saved in Keychain" : "sk-ant-…"))
                    .accessibilityIdentifier("settings-api-key")
                HStack {
                    Button("Save key") { saveKey(apiKeyDraft) }.disabled(apiKeyDraft.isEmpty)
                    Button("Remove key", role: .destructive) { saveKey("") }.disabled(!app.hasAPIKey)
                    if let apiKeyMessage { Text(apiKeyMessage).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Claude (LLM judge)")
            } footer: {
                Text("By default the judge uses your own Claude plan through Claude Code. An API key is an optional, pay-per-use alternative; it's stored in your login Keychain. Choose which to use in the LLM-as-a-judge tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                LabeledContent("Version", value: updater.version)
                if updater.isConfigured {
                    Toggle("Check for updates automatically", isOn: $automaticallyChecks)
                        .onChange(of: automaticallyChecks) { updater.automaticallyChecks = automaticallyChecks }
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } else {
                    Text("Updates aren't configured in this build (development build).")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onAppear { automaticallyChecks = updater.isConfigured && updater.automaticallyChecks }
    }

    private func saveKey(_ key: String) {
        if KeychainStore.saveAPIKey(key) {
            app.hasAPIKey = KeychainStore.readAPIKey() != nil
            apiKeyMessage = key.isEmpty ? "Key removed." : "Key saved in Keychain."
            apiKeyDraft = ""
        } else {
            apiKeyMessage = "The Keychain refused to save the key."
        }
    }
}
