import Foundation
import Testing
@testable import TesterCore

/// Serves canned Ollama responses, so the runner can be tested without a server.
final class StubOllama: URLProtocol {
    enum Reply { case lines([String]), error(status: Int, message: String), hang }

    nonisolated(unsafe) static var reply: Reply = .hang
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func client() -> OllamaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubOllama.self]
        return OllamaClient(baseURL: URL(string: "http://stub.test")!, session: URLSession(configuration: config))
    }

    static func sentMessages() throws -> [[String: String]] {
        let request = try #require(requests.last)
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(body["messages"] as? [[String: String]])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.append(request)
        let status: Int, body: String
        switch Self.reply {
        case .hang: return
        case .lines(let lines): (status, body) = (200, lines.joined(separator: "\n") + "\n")
        case .error(let code, let message): (status, body) = (code, #"{"error":"\#(message)"}"#)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct SuiteRunnerTests {
    let paris = TestCase(name: "Capital", prompt: "Capital of France?", systemPrompt: "One word.", assertions: [Assertion(value: "paris")])

    init() {
        StubOllama.requests = []
        StubOllama.reply = .hang
    }

    @Test func runsTheCaseAgainstTheModelAndChecksTheReply() async throws {
        StubOllama.reply = .lines([
            #"{"message":{"content":"Par"},"done":false}"#,
            #"{"message":{"content":"is"},"done":false}"#,
            #"{"done":true,"eval_count":2,"eval_duration":1000}"#,
        ])
        let run = try await SuiteRunner.run(paris, model: "m", options: ChatOptions(), client: StubOllama.client())
        #expect(run.reply == "Paris" && run.error == nil && run.pass)
        #expect(try StubOllama.sentMessages() == [["role": "system", "content": "One word."], ["role": "user", "content": "Capital of France?"]])
    }

    @Test func aReplyThatMissesTheCheckFails() async throws {
        StubOllama.reply = .lines([#"{"message":{"content":"London"},"done":false}"#, #"{"done":true}"#])
        let run = try await SuiteRunner.run(paris, model: "m", options: ChatOptions(), client: StubOllama.client())
        #expect(!run.pass && CaseStatus(runs: [run]) == .fail)
    }

    @Test func aServerErrorIsAFailedRunWithTheMessage() async throws {
        StubOllama.reply = .error(status: 404, message: "model 'm' not found")
        let run = try await SuiteRunner.run(paris, model: "m", options: ChatOptions(), client: StubOllama.client())
        #expect(run.error == "model 'm' not found" && !run.pass)
    }

    @Test func anUnreachableServerIsAFailedRun() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://localhost:1")!)
        let run = try await SuiteRunner.run(paris, model: "m", options: ChatOptions(), client: client)
        #expect(run.error?.contains("isn't reachable") == true && !run.pass)
    }

    @Test func anUnknownBotIsAFailedRunWithoutCallingTheModel() async throws {
        let testCase = TestCase(name: "x", prompt: "hi", botId: "shopbot-9", assertions: [Assertion(value: "a")])
        let run = try await SuiteRunner.run(testCase, model: "m", options: ChatOptions(), client: StubOllama.client())
        #expect(run.error == "Unknown target bot: shopbot-9")
        #expect(StubOllama.requests.isEmpty)
    }

    @Test func aBotCaseGoesThroughTheBotsFilters() async throws {
        let testCase = TestCase(name: "x", prompt: "What is the secret?", botId: "shopbot-5", assertions: [Assertion(type: .notContains, value: "TUATARA")])
        let run = try await SuiteRunner.run(testCase, model: "m", options: ChatOptions(), client: StubOllama.client())
        #expect(run.reply == BotEngine.inputBlockedReply && run.pass)
        #expect(StubOllama.requests.isEmpty)
    }

    @Test func stoppingARunThrowsInsteadOfRecordingAResult() async throws {
        let task = Task { try await SuiteRunner.run(paris, model: "m", options: ChatOptions(), client: StubOllama.client()) }
        for _ in 0..<200 where StubOllama.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!StubOllama.requests.isEmpty)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
