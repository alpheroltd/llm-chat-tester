import Foundation

public enum OllamaError: LocalizedError, Equatable {
    case unreachable(URL)
    case server(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .unreachable(let url): "Ollama isn't reachable at \(url.absoluteString). Is it running?"
        case .server(let message): message
        case .badResponse: "Unexpected response from Ollama."
        }
    }
}

public struct PullProgress: Sendable, Equatable {
    public var status: String
    public var completed: Int64?
    public var total: Int64?

    public var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

/// Talks to a local Ollama server over its HTTP API. Replies stream as newline-delimited JSON.
public struct OllamaClient: Sendable {
    public var baseURL: URL
    private let session: URLSession

    public static let defaultURL = URL(string: "http://localhost:11434")!

    public init(baseURL: URL = OllamaClient.defaultURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Models

    public func listModels() async throws -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        let data = try await perform(URLRequest(url: baseURL.appending(path: "api/tags")))
        return try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).sorted()
    }

    public func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        struct Line: Decodable { let status: String?; let completed: Int64?; let total: Int64?; let error: String? }
        return lineStream(path: "api/pull", body: ["model": model, "stream": true] as [String: any Sendable]) { line in
            let decoded = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
            if let error = decoded.error { throw OllamaError.server(error) }
            return PullProgress(status: decoded.status ?? "", completed: decoded.completed, total: decoded.total)
        }
    }

    // MARK: Chat

    public func streamChat(model: String, messages: [ChatMessage], options: ChatOptions) -> AsyncThrowingStream<ChatEvent, Error> {
        var ollamaOptions: [String: any Sendable] = ["temperature": options.temperature]
        if let seed = options.seed { ollamaOptions["seed"] = seed }
        if let maxTokens = options.maxTokens { ollamaOptions["num_predict"] = maxTokens }
        let body: [String: any Sendable] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "options": ollamaOptions,
            "stream": true,
        ]
        return lineStream(path: "api/chat", body: body) { try Self.parseChatLine($0) }
    }

    /// Parses one NDJSON line from /api/chat. Returns nil for lines that carry nothing useful.
    public static func parseChatLine(_ line: String) throws -> ChatEvent? {
        struct Chunk: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
            let done: Bool?
            let error: String?
            let eval_count: Int?
            let eval_duration: Int?
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let chunk = try JSONDecoder().decode(Chunk.self, from: Data(trimmed.utf8))
        if let error = chunk.error { throw OllamaError.server(error) }
        if chunk.done == true { return .done(ChatStats(evalCount: chunk.eval_count, evalDurationNanos: chunk.eval_duration)) }
        if let content = chunk.message?.content, !content.isEmpty { return .token(content) }
        return nil
    }

    // MARK: Plumbing

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Self.check(response, data: data)
            return data
        } catch let error as URLError where Self.isConnectionFailure(error) {
            throw OllamaError.unreachable(baseURL)
        }
    }

    private func lineStream<T: Sendable>(
        path: String,
        body: [String: any Sendable],
        parse: @escaping @Sendable (String) throws -> T?
    ) -> AsyncThrowingStream<T, Error> {
        let url = baseURL.appending(path: path)
        let session = session
        let baseURL = baseURL
        let bodyData = try? JSONSerialization.data(withJSONObject: body)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = bodyData
                    request.timeoutInterval = 600
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        try Self.check(response, data: data)
                    }
                    for try await line in bytes.lines {
                        if let value = try parse(line) { continuation.yield(value) }
                    }
                    continuation.finish()
                } catch let error as URLError where Self.isConnectionFailure(error) {
                    continuation.finish(throwing: OllamaError.unreachable(baseURL))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OllamaError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct ErrorBody: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OllamaError.server(message)
        }
    }

    private static func isConnectionFailure(_ error: URLError) -> Bool {
        [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut].contains(error.code)
    }
}
