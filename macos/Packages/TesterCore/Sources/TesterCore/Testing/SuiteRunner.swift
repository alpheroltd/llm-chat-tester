import Foundation

public enum SuiteRunner {
    public enum RunError: LocalizedError {
        case unknownBot(String)
        public var errorDescription: String? {
            switch self {
            case .unknownBot(let id): "Unknown target bot: \(id)"
            }
        }
    }

    /// Gets the reply a test case is checked against: from the model directly (with the case's system prompt),
    /// or through a target bot (hidden prompt and filters applied).
    public static func reply(for testCase: TestCase, model: String, options: ChatOptions, client: OllamaClient) async throws -> String {
        let message = [ChatMessage(role: .user, content: testCase.prompt)]
        if !testCase.botId.isEmpty {
            guard let bot = BotEngine.bot(id: testCase.botId) else { throw RunError.unknownBot(testCase.botId) }
            return try await BotEngine.respond(bot: bot, conversation: message, model: model, options: options, client: client).text
        }
        var reply = ""
        for try await event in client.streamChat(model: model, messages: buildMessages(systemPrompt: testCase.systemPrompt, conversation: message), options: options) {
            if case .token(let token) = event { reply += token }
        }
        return reply
    }

    /// Runs one case once and checks the reply.
    public static func run(_ testCase: TestCase, model: String, options: ChatOptions, client: OllamaClient) async throws -> CaseRun {
        let started = ContinuousClock.now
        do {
            let reply = try await reply(for: testCase, model: model, options: options, client: client)
            return CaseRun(reply: reply, assertions: testCase.assertions, seconds: (ContinuousClock.now - started).seconds)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return CaseRun(error: error.localizedDescription, seconds: (ContinuousClock.now - started).seconds)
        }
    }

    /// e.g. "✅ 3 passed · ⚠️ 1 flaky · ❌ 1 failed"
    public static func summary(_ statuses: [CaseStatus]) -> String {
        let count = { (s: CaseStatus) in statuses.filter { $0 == s }.count }
        return "✅ \(count(.pass)) passed · ⚠️ \(count(.flaky)) flaky · ❌ \(count(.fail)) failed"
    }
}
