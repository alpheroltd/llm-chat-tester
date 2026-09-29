import Foundation
import Observation
import TesterCore

struct VariantRun: Equatable {
    var options: ChatOptions
    var replies: [String] = []
    var errors: [String] = []
    var total: Int
    var isRunning = true
    var uniqueCount: Int { uniqueAnswerCount(replies) }
}

struct ChatEntry: Identifiable, Equatable {
    enum Role { case user, assistant, error }
    let id: UUID
    var role: Role
    var text: String
    var context: MessageContext?
    var meta: String?
    var isStreaming = false
    /// A user message whose request failed; left out of history so it can be retried.
    var failed = false
    var variants: VariantRun?
    var flag: Flag?

    init(id: UUID = UUID(), role: Role, text: String, context: MessageContext? = nil, meta: String? = nil, isStreaming: Bool = false, failed: Bool = false, flag: Flag? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
        self.meta = meta
        self.isStreaming = isStreaming
        self.failed = failed
        self.flag = flag
    }

    var saved: SessionMessage {
        let role: SessionMessage.Role = switch self.role { case .user: .user; case .assistant: .assistant; case .error: .error }
        return SessionMessage(id: id, role: role, text: text, context: context, meta: meta, flag: flag, failed: failed)
    }

    init(_ saved: SessionMessage) {
        let role: Role = switch saved.role { case .user: .user; case .assistant: .assistant; case .error: .error }
        self.init(id: saved.id, role: role, text: saved.text, context: saved.context, meta: saved.meta, failed: saved.failed, flag: saved.flag)
    }
}

@MainActor @Observable
final class ChatViewModel {
    private(set) var entries: [ChatEntry] = []
    private(set) var isSending = false
    /// Composer text. Lives here so missions can insert a suggested prompt.
    var draft = ""
    private(set) var sessions: [ChatSession] = []
    private var session: ChatSession?
    private var sendTask: Task<Void, Never>?
    private let store = SessionStore()

    static let variantRuns = 5

    init() {
        sessions = store.all()
    }

    // MARK: History

    /// Turns sent to the model: everything before `index`, minus errors, failed sends and empty replies.
    func conversation(before index: Int? = nil) -> [ChatMessage] {
        entries.prefix(index ?? entries.count).compactMap { entry in
            switch entry.role {
            case .user where !entry.failed: ChatMessage(role: .user, content: entry.text)
            case .assistant where !entry.text.isEmpty: ChatMessage(role: .assistant, content: entry.text)
            default: nil
            }
        }
    }

    var savedMessages: [SessionMessage] { entries.map(\.saved) }

    /// Starts a new chat. The current one stays in History.
    func clear() {
        sendTask?.cancel()
        persist()
        entries.removeAll()
        session = nil
    }

    func stop() { sendTask?.cancel() }

    func open(_ saved: ChatSession) {
        sendTask?.cancel()
        persist()
        session = saved
        entries = saved.messages.map(ChatEntry.init)
    }

    func deleteSession(_ saved: ChatSession) {
        store.delete(saved.id)
        if session?.id == saved.id {
            session = nil
            entries.removeAll()
        }
        sessions = store.all()
    }

    /// Saves the current chat (if it has anything in it) and refreshes the History list.
    private func persist() {
        guard !entries.isEmpty else { return }
        var current = session ?? ChatSession(modeLabel: entries.first?.context?.modeLabel ?? "Free chat")
        current.messages = savedMessages
        current.updated = Date()
        session = current
        try? store.save(current)
        sessions = store.all()
    }

    // MARK: Flags

    func setFlag(_ flag: Flag?, for id: UUID) {
        update(id) { $0.flag = flag }
        persist()
    }

    // MARK: Sending

    func send(app: AppState) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        guard !app.selectedModel.isEmpty else {
            entries.append(ChatEntry(role: .error, text: "No model selected. Install one with Ollama, then press ↻."))
            return
        }
        let context = app.messageContext()
        entries.append(ChatEntry(role: .user, text: text, context: context))
        let userID = entries[entries.count - 1].id
        let reply = ChatEntry(role: .assistant, text: "", context: context, isStreaming: true)
        entries.append(reply)
        let history = conversation(before: entries.count - 1)
        let client = app.ollama
        let bot = context.botId.flatMap(BotEngine.bot(id:))

        isSending = true
        sendTask = Task { [weak self] in
            let started = ContinuousClock.now
            var stats: ChatStats?
            var stopped = false
            var blocked: String?
            do {
                if let bot {
                    let result = try await BotEngine.respond(
                        bot: bot, conversation: history, model: context.model, options: context.options, client: client,
                        onToken: { text in await MainActor.run { self?.update(reply.id) { $0.text = text } } })
                    try Task.checkCancellation()
                    self?.update(reply.id) { $0.text = result.text }
                    stats = result.stats
                    blocked = result.blocked
                    if result.leaked { app.recordLeak(botId: bot.id) }
                } else {
                    let messages = buildMessages(systemPrompt: context.systemPrompt, conversation: history)
                    for try await event in client.streamChat(model: context.model, messages: messages, options: context.options) {
                        switch event {
                        case .token(let token): self?.update(reply.id) { $0.text += token }
                        case .done(let s): stats = s
                        }
                    }
                    try Task.checkCancellation()
                }
            } catch is CancellationError {
                stopped = true
            } catch let error as URLError where error.code == .cancelled {
                stopped = true
            } catch {
                self?.fail(replyID: reply.id, userID: userID, message: error.localizedDescription)
            }
            var meta = Self.formatMeta(context, elapsed: ContinuousClock.now - started, stats: stats)
            if let blocked { meta += " · 🛡 blocked by \(blocked) filter" }
            if stopped { meta += " · stopped" }
            self?.update(reply.id) {
                $0.isStreaming = false
                $0.meta = meta
            }
            self?.isSending = false
            self?.persist()
        }
    }

    private func fail(replyID: UUID, userID: UUID, message: String) {
        entries.removeAll { $0.id == replyID }
        update(userID) { $0.failed = true }
        entries.append(ChatEntry(role: .error, text: message))
    }

    private func update(_ id: UUID, _ change: (inout ChatEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    // MARK: Run ×5

    /// Re-sends the conversation up to this reply several times, with the *current* settings,
    /// and records the answers without adding them to history.
    func runVariants(for replyID: UUID, app: AppState) {
        guard let index = entries.firstIndex(where: { $0.id == replyID }),
              let context = entries[index].context else { return }
        let options = app.options
        let history = conversation(before: index)
        let client = app.ollama
        let bot = context.botId.flatMap(BotEngine.bot(id:))
        update(replyID) { $0.variants = VariantRun(options: options, total: Self.variantRuns) }

        Task { [weak self] in
            for _ in 0..<Self.variantRuns {
                do {
                    var reply = ""
                    if let bot {
                        let result = try await BotEngine.respond(bot: bot, conversation: history, model: context.model, options: options, client: client)
                        reply = result.text
                        if result.leaked { app.recordLeak(botId: bot.id) }
                    } else {
                        let messages = buildMessages(systemPrompt: context.systemPrompt, conversation: history)
                        for try await event in client.streamChat(model: context.model, messages: messages, options: options) {
                            if case .token(let token) = event { reply += token }
                        }
                    }
                    self?.update(replyID) { $0.variants?.replies.append(reply) }
                } catch {
                    self?.update(replyID) { $0.variants?.errors.append(error.localizedDescription) }
                }
            }
            self?.update(replyID) { $0.variants?.isRunning = false }
        }
    }

    // MARK: Formatting

    static func formatMeta(_ context: MessageContext, elapsed: Duration, stats: ChatStats?) -> String {
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        var parts = [context.model, String(format: "%.2fs", seconds)]
        if let count = stats?.evalCount, let tps = stats?.tokensPerSecond {
            parts.append("\(count) tokens")
            parts.append(String(format: "%.1f tok/s", tps))
        }
        parts.append(context.options.summary)
        return parts.joined(separator: " · ")
    }
}
