import Foundation
import Observation
import TesterCore

enum ServiceStatus: Equatable {
    case checking
    case ok(String)
    case problem(String)

    var isOK: Bool { if case .ok = self { true } else { false } }
    var label: String {
        switch self {
        case .checking: "Checking…"
        case .ok(let text), .problem(let text): text
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case learn = "Learn"
    case chat = "Chat"
    case testCases = "Test cases"
    case judge = "LLM-as-a-judge"
    var id: String { rawValue }
}

enum ChatMode: String, CaseIterable, Identifiable {
    case free = "Free chat"
    case targetBots = "Target bots"
    case missions = "Missions"
    var id: String { rawValue }
}

/// App-wide state: connection status, selected model and the generation settings in the sidebar.
@MainActor @Observable
final class AppState {
    private let defaults = UserDefaults.standard

    /// Remembered between launches; new testers start on Learn.
    var tab: AppTab {
        didSet { defaults.set(tab.rawValue, forKey: "tab") }
    }
    var mode: ChatMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode") }
    }

    // Target bots
    var selectedBotID: String {
        didSet { defaults.set(selectedBotID, forKey: "selectedBotID") }
    }
    private(set) var beatenLevels: Set<String> {
        didSet { defaults.set(Array(beatenLevels), forKey: "beatenLevels") }
    }
    /// The bot whose secret just leaked, for the "Level beaten!" banner (nil = no banner).
    var winBannerBotID: String?

    // Missions
    var selectedMissionID: String {
        didSet { defaults.set(selectedMissionID, forKey: "selectedMissionID") }
    }
    private(set) var completedMissions: Set<String> {
        didSet { defaults.set(Array(completedMissions), forKey: "completedMissions") }
    }

    var models: [String] = []
    var ollamaStatus: ServiceStatus = .checking
    var claudeStatus: ServiceStatus = .checking

    var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: "selectedModel") }
    }
    var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: "systemPrompt") }
    }
    var temperature: Double {
        didSet { defaults.set(temperature, forKey: "temperature") }
    }
    /// Text fields, so "blank" can mean random seed / no limit.
    var seedText: String {
        didSet { defaults.set(seedText, forKey: "seed") }
    }
    var maxTokensText: String {
        didSet { defaults.set(maxTokensText, forKey: "maxTokens") }
    }
    var ollamaURLText: String {
        didSet { defaults.set(ollamaURLText, forKey: "ollamaURL") }
    }
    var claudePathOverride: String {
        didSet { defaults.set(claudePathOverride, forKey: "claudePath") }
    }
    /// Whether an Anthropic API key is saved in the Keychain (the key itself is only read when judging).
    var hasAPIKey = KeychainStore.readAPIKey() != nil

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        selectedModel = defaults.string(forKey: "selectedModel") ?? ""
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? ""
        temperature = defaults.object(forKey: "temperature") != nil ? defaults.double(forKey: "temperature") : 0.8
        seedText = defaults.string(forKey: "seed") ?? ""
        maxTokensText = defaults.string(forKey: "maxTokens") ?? ""
        ollamaURLText = defaults.string(forKey: "ollamaURL") ?? OllamaClient.defaultURL.absoluteString
        claudePathOverride = defaults.string(forKey: "claudePath") ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        tab = defaults.string(forKey: "tab").flatMap(AppTab.init(rawValue:)) ?? .learn
        mode = defaults.string(forKey: "mode").flatMap(ChatMode.init(rawValue:)) ?? .free
        selectedBotID = defaults.string(forKey: "selectedBotID").flatMap { BotEngine.bot(id: $0)?.id } ?? BotEngine.bots[0].id
        beatenLevels = Set(defaults.stringArray(forKey: "beatenLevels") ?? [])
        selectedMissionID = defaults.string(forKey: "selectedMissionID").flatMap { id in Content.missions.first { $0.id == id }?.id }
            ?? Content.missions[0].id
        completedMissions = Set(defaults.stringArray(forKey: "completedMissions") ?? [])
    }

    var selectedBot: Bot { BotEngine.bot(id: selectedBotID) ?? BotEngine.bots[0] }
    var selectedMission: Mission { Content.missions.first { $0.id == selectedMissionID } ?? Content.missions[0] }

    /// What the next message is sent with: model, settings, and either the sidebar system prompt or a target bot.
    func messageContext() -> MessageContext {
        switch mode {
        case .targetBots:
            MessageContext(model: selectedModel, systemPrompt: "", options: options, modeLabel: "Target bot: \(selectedBot.name)", botId: selectedBot.id)
        case .missions:
            MessageContext(model: selectedModel, systemPrompt: systemPrompt, options: options, modeLabel: "Mission: \(selectedMission.title)")
        case .free:
            MessageContext(model: selectedModel, systemPrompt: systemPrompt, options: options, modeLabel: "Free chat")
        }
    }

    func recordLeak(botId: String) {
        beatenLevels.insert(botId)
        winBannerBotID = botId
    }

    func toggleMissionComplete(_ id: String) {
        if completedMissions.contains(id) { completedMissions.remove(id) } else { completedMissions.insert(id) }
    }

    /// Applies a mission's setup: system prompt, settings, or switching to another mode/tab.
    func apply(_ setup: Mission.Setup) {
        if let prompt = setup.systemPrompt { systemPrompt = prompt }
        if let settings = setup.settings {
            if let t = settings.temperature { temperature = t }
            if let seed = settings.seed { seedText = String(seed) }
        }
        switch setup.goTo {
        case .bot: mode = .targetBots; tab = .chat
        case .tests: tab = .testCases
        case .judge: tab = .judge
        case nil: break
        }
    }

    var ollama: OllamaClient {
        OllamaClient(baseURL: URL(string: ollamaURLText) ?? OllamaClient.defaultURL)
    }

    var options: ChatOptions {
        ChatOptions(
            temperature: (temperature * 10).rounded() / 10,
            seed: Int(seedText.trimmingCharacters(in: .whitespaces)),
            maxTokens: Int(maxTokensText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        )
    }

    func refreshModels() async {
        ollamaStatus = .checking
        do {
            models = try await ollama.listModels()
            if !models.contains(selectedModel) { selectedModel = models.first ?? "" }
            ollamaStatus = models.isEmpty ? .problem("No models installed") : .ok("Ollama connected")
        } catch {
            models = []
            ollamaStatus = .problem(error.localizedDescription)
        }
    }

    func refreshClaude() async {
        claudeStatus = .checking
        guard let path = await ClaudeCLI.locate(override: claudePathOverride) else {
            claudeStatus = .problem("Claude Code not found (optional)")
            return
        }
        if let version = await ClaudeCLI.version(at: path) {
            claudeStatus = .ok("Claude Code \(version.split(separator: " ").first ?? "")")
        } else {
            claudeStatus = .problem("Claude Code found but won't run")
        }
    }
}
