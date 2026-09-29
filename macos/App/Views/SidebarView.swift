import SwiftUI
import TesterCore
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat
    @State private var exportingReport = false
    @State private var showingHistory = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section("Model") {
                HStack {
                    Picker("Model", selection: $app.selectedModel) {
                        if app.models.isEmpty { Text("No models").tag("") }
                        ForEach(app.models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("model-select")
                    Button {
                        Task { await app.refreshModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh models (after `ollama pull`)")
                    .accessibilityIdentifier("refresh-models")
                }
                StatusBadge(status: app.ollamaStatus)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("status")
            }

            Section {
                Picker("Mode", selection: Binding(get: { app.mode }, set: { switchMode(to: $0) })) {
                    ForEach(ChatMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityIdentifier("mode")
            } header: {
                Text("Mode")
            } footer: {
                Text("Switching starts a new chat. Earlier chats are kept in History.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            switch app.mode {
            case .targetBots: BotPanel()
            case .missions: MissionPanel()
            case .free: EmptyView()
            }

            if app.mode != .targetBots {
                Section("System prompt") {
                    TextEditor(text: $app.systemPrompt)
                        .font(.body)
                        .frame(minHeight: 70, maxHeight: 140)
                        .accessibilityIdentifier("system-prompt")
                    Text("Hidden instructions the bot follows. Real client bots are configured like this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Settings") {
                LabeledContent("Temperature") {
                    HStack {
                        Slider(value: $app.temperature, in: 0...2, step: 0.1)
                            .accessibilityIdentifier("temperature")
                        Text(app.temperature, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                }
                TextField("Seed", text: $app.seedText, prompt: Text("random"))
                    .accessibilityIdentifier("seed")
                TextField("Max tokens", text: $app.maxTokensText, prompt: Text("no limit"))
                    .accessibilityIdentifier("max-tokens")
                Text("Temperature = randomness (0 = most predictable). The same seed + temperature gives the same reply, which makes bugs reproducible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Export report…") { exportingReport = true }
                        .disabled(chat.entries.isEmpty)
                        .accessibilityIdentifier("export-report")
                    Button("History…") { showingHistory = true }
                        .accessibilityIdentifier("history")
                    Button("New chat") { newChat() }
                        .disabled(chat.entries.isEmpty)
                        .accessibilityIdentifier("clear-chat")
                }
            } header: {
                Text("Session")
            } footer: {
                Text("Flag replies with ⚑ as you go. The report turns them into bug write-ups.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileExporter(isPresented: $exportingReport,
                      document: MarkdownDocument(text: ReportBuilder.markdown(for: chat.savedMessages)),
                      contentType: .markdownText,
                      defaultFilename: "chatbot-test-report-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")).md") { _ in }
        .sheet(isPresented: $showingHistory) { HistoryView() }
    }

    private func switchMode(to mode: ChatMode) {
        guard mode != app.mode else { return }
        newChat()
        app.mode = mode
    }

    private func newChat() {
        chat.clear()
        app.winBannerBotID = nil
    }
}

// MARK: - Target bots

private struct BotPanel: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat

    var body: some View {
        let bot = app.selectedBot
        Section("Break the bot") {
            HStack(spacing: 6) {
                ForEach(BotEngine.bots) { level in
                    let selected = level.id == app.selectedBotID
                    Button(app.beatenLevels.contains(level.id) ? "✓ \(level.level)" : "\(level.level)") {
                        guard !selected else { return }
                        chat.clear()
                        app.winBannerBotID = nil
                        app.selectedBotID = level.id
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .accentColor : nil)
                    .foregroundStyle(app.beatenLevels.contains(level.id) ? .green : .primary)
                    .accessibilityIdentifier("level-\(level.level)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("🎯 Goal: get ShopBot (the Kiwi Gadgets support bot) to reveal the secret staff discount code.").bold()
            Text(bot.briefing)
            Text("Defences: \(bot.defences.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
            Text("Beaten \(app.beatenLevels.count) of \(BotEngine.bots.count) levels.").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("levels-beaten")
            if app.beatenLevels.contains(bot.id) {
                DisclosureGroup("Debrief (already beaten)") { Text(bot.debrief).font(.callout) }
            }
        }
    }
}

// MARK: - Missions

private struct MissionPanel: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat

    var body: some View {
        @Bindable var app = app
        let mission = app.selectedMission
        let done = app.completedMissions.contains(mission.id)
        Section {
            Picker("Mission", selection: $app.selectedMissionID) {
                ForEach(Content.missions) { m in
                    Text("\(app.completedMissions.contains(m.id) ? "✓" : "○")  \(m.title)").tag(m.id)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("mission-select")

            Text(mission.category).font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            (Text("Goal: ").bold() + Text(mission.goal))
            if let setup = mission.setup {
                HStack(alignment: .firstTextBaseline) {
                    Button("Apply setup") {
                        if setup.goTo == .bot { chat.clear() }
                        app.apply(setup)
                    }
                    .accessibilityIdentifier("mission-apply-setup")
                    Text(setup.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !mission.prompts.isEmpty {
                Text("Try these prompts (click to use):").font(.caption.bold())
                ForEach(mission.prompts, id: \.self) { prompt in
                    Button {
                        chat.draft = prompt
                        app.tab = .chat
                    } label: {
                        Text(verbatim: prompt).font(.callout).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("mission-prompt")
                }
            }
            DisclosureGroup("💡 Hints") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(mission.hints.enumerated()), id: \.offset) { i, hint in Text("\(i + 1). \(hint)").font(.callout) }
                }
            }
            (Text("🐞 What a bug looks like: ").bold() + Text(mission.bug)).font(.callout)
            (Text("🌍 In the real world: ").bold() + Text(mission.realWorld)).font(.callout).foregroundStyle(.secondary)
            Button(done ? "✓ Completed (undo)" : "Mark complete") { app.toggleMissionComplete(mission.id) }
                .buttonStyle(.borderedProminent)
                .tint(done ? .gray : .accentColor)
                .accessibilityIdentifier("mission-complete")
        } header: {
            HStack {
                Text("Missions")
                Spacer()
                Text("\(app.completedMissions.count) of \(Content.missions.count) complete")
                    .accessibilityIdentifier("mission-progress")
            }
        }
    }
}

// MARK: - Export

struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownText, .plainText]
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}
