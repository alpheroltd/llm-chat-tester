import SwiftUI
import TesterCore

/// First-run checklist: is Ollama running, is there a model, is Claude Code available (optional).
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Binding var isPresented: Bool
    @State private var pullStatus: String?
    @State private var pullFraction: Double?
    @State private var pullTask: Task<Void, Never>?

    static let recommendedModel = "llama3.2:3b"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to LLM Chat Tester").font(.title2.bold())
            Text("A training tool for testing chatbots. The chatbot you test runs on your Mac with Ollama; Claude is only needed later, for the LLM judge.")
                .foregroundStyle(.secondary)

            step(
                number: 1,
                title: "Ollama is running",
                status: ollamaRunning ? .ok("Connected") : app.ollamaStatus,
                detail: "Install Ollama from ollama.com and open it (or run `brew install ollama && brew services start ollama`)."
            ) {
                Link("Download Ollama", destination: URL(string: "https://ollama.com/download")!)
            }

            step(
                number: 2,
                title: "A model is installed",
                status: app.models.isEmpty ? .problem("No models yet") : .ok(app.models.joined(separator: ", ")),
                detail: "\(Self.recommendedModel) is about 2 GB and runs well on any Apple Silicon Mac."
            ) {
                if let pullStatus {
                    VStack(alignment: .leading) {
                        if let pullFraction { ProgressView(value: pullFraction) } else { ProgressView().controlSize(.small) }
                        Text(pullStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 260)
                } else {
                    Button("Download \(Self.recommendedModel)", action: pull)
                        .disabled(!ollamaRunning)
                        .accessibilityIdentifier("onboarding-pull")
                }
            }

            step(
                number: 3,
                title: "Claude Code (optional)",
                status: app.claudeStatus,
                detail: "Used by the LLM judge. Install Claude Code and run `claude` once in Terminal to log in with your own Claude plan."
            ) {
                Link("Install Claude Code", destination: URL(string: "https://claude.com/claude-code")!)
            }

            HStack {
                Button("Check again") {
                    Task {
                        await app.refreshModels()
                        await app.refreshClaude()
                    }
                }
                Spacer()
                Button(ready ? "Get started" : "Continue anyway") {
                    pullTask?.cancel()
                    app.hasCompletedOnboarding = true
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-done")
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var ollamaRunning: Bool {
        switch app.ollamaStatus {
        case .ok: true
        case .problem(let text): text == "No models installed"
        case .checking: false
        }
    }

    private var ready: Bool { ollamaRunning && !app.models.isEmpty }

    private func step(number: Int, title: String, status: ServiceStatus, detail: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.isOK ? "checkmark.circle.fill" : (status == .checking ? "circle.dotted" : "exclamationmark.circle"))
                .font(.title2)
                .foregroundStyle(status.isOK ? .green : (status == .checking ? .gray : .orange))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)").font(.headline)
                Text(status.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(.init(detail)).font(.callout)
                action()
            }
        }
    }

    private func pull() {
        let client = app.ollama
        pullStatus = "Starting download…"
        pullTask = Task {
            do {
                for try await progress in client.pull(model: Self.recommendedModel) {
                    pullStatus = progress.status
                    pullFraction = progress.fraction
                }
                await app.refreshModels()
                pullStatus = nil
            } catch {
                pullStatus = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}
