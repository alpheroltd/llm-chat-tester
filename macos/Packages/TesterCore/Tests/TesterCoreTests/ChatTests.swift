import Foundation
import Testing
@testable import TesterCore

@Suite struct ChatParsingTests {
    @Test func parsesTokenLine() throws {
        let line = #"{"model":"llama3.2:3b","message":{"role":"assistant","content":"Hel"},"done":false}"#
        #expect(try OllamaClient.parseChatLine(line) == .token("Hel"))
    }

    @Test func parsesDoneLineWithStats() throws {
        let line = #"{"model":"m","message":{"role":"assistant","content":""},"done":true,"eval_count":57,"eval_duration":1331000000}"#
        let event = try OllamaClient.parseChatLine(line)
        guard case .done(let stats) = event else { Issue.record("expected done, got \(String(describing: event))"); return }
        #expect(stats.evalCount == 57)
        #expect(abs((stats.tokensPerSecond ?? 0) - 42.8) < 0.1)
    }

    @Test func skipsBlankAndEmptyContentLines() throws {
        #expect(try OllamaClient.parseChatLine("") == nil)
        #expect(try OllamaClient.parseChatLine("   ") == nil)
        #expect(try OllamaClient.parseChatLine(#"{"message":{"content":""},"done":false}"#) == nil)
    }

    @Test func surfacesServerErrors() {
        #expect(throws: OllamaError.server("model 'nope' not found")) {
            try OllamaClient.parseChatLine(#"{"error":"model 'nope' not found"}"#)
        }
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try OllamaClient.parseChatLine("not json") }
    }
}

@Suite struct ChatHelperTests {
    @Test func buildMessagesAddsSystemPromptOnlyWhenPresent() {
        let convo = [ChatMessage(role: .user, content: "hi")]
        #expect(buildMessages(systemPrompt: "  ", conversation: convo) == convo)
        let withSystem = buildMessages(systemPrompt: " Be nice ", conversation: convo)
        #expect(withSystem.first == ChatMessage(role: .system, content: "Be nice"))
        #expect(withSystem.count == 2)
    }

    @Test func optionsSummaryMatchesWebApp() {
        #expect(ChatOptions().summary == "temp 0.8 · seed random")
        #expect(ChatOptions(temperature: 0, seed: 42, maxTokens: 256).summary == "temp 0 · seed 42 · max 256 tokens")
    }

    @Test func uniqueAnswersIgnoreWhitespace() {
        #expect(uniqueAnswerCount(["Paris.", " Paris.\n", "Paris!"]) == 2)
        #expect(uniqueAnswerCount([]) == 0)
    }

    @Test func claudeCandidatePathsIncludeUserLocalBin() {
        #expect(ClaudeCLI.candidatePaths(home: "/Users/x").first == "/Users/x/.local/bin/claude")
    }
}

/// Talks to the real local Ollama. Skipped automatically when it isn't running.
@Suite struct OllamaLiveTests {
    static let ollamaUp: Bool = {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var up = false
        URLSession.shared.dataTask(with: URL(string: "http://localhost:11434/api/tags")!) { _, r, _ in
            up = (r as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 2)
        return up
    }()

    @Test(.enabled(if: ollamaUp)) func streamsAReply() async throws {
        let client = OllamaClient()
        let models = try await client.listModels()
        let model = try #require(models.first)
        var reply = ""
        var sawDone = false
        for try await event in client.streamChat(
            model: model,
            messages: [ChatMessage(role: .user, content: "What is the capital of France? One word.")],
            options: ChatOptions(temperature: 0, seed: 1)
        ) {
            switch event {
            case .token(let t): reply += t
            case .done: sawDone = true
            }
        }
        #expect(sawDone)
        #expect(reply.localizedCaseInsensitiveContains("paris"))
    }

    @Test(.enabled(if: ollamaUp)) func unknownModelIsAClearError() async {
        await #expect(throws: OllamaError.self) {
            for try await _ in OllamaClient().streamChat(model: "nope-not-a-model", messages: [ChatMessage(role: .user, content: "hi")], options: ChatOptions()) {}
        }
    }

    @Test func unreachableServerIsAClearError() async {
        let client = OllamaClient(baseURL: URL(string: "http://localhost:1")!)
        await #expect(throws: OllamaError.unreachable(URL(string: "http://localhost:1")!)) {
            _ = try await client.listModels()
        }
    }

    @Test func claudeCLIVersionRuns() async throws {
        guard let path = await ClaudeCLI.locate() else { return } // not installed on this machine: nothing to check
        let version = await ClaudeCLI.version(at: path)
        #expect(version?.contains("Claude Code") == true)
    }
}
