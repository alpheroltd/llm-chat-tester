import Foundation

/// Grades through the Claude API with an Anthropic API key (raw HTTP: there's no official Swift SDK).
/// Uses structured outputs (`output_config.format`) so the verdict always matches the schema.
public struct AnthropicAPIJudge: JudgeRunner {
    public var apiKey: String
    public var baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public static func requestBody(_ request: JudgeRequest, model: JudgeModel) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.apiID,
            "max_tokens": 4096,
            "system": JudgePrompt.system,
            "messages": [["role": "user", "content": JudgePrompt.userMessage(for: request)]],
            "output_config": ["format": ["type": "json_schema", "schema": JudgePrompt.schemaObject()]],
        ]
        // Claude Opus 5 can decline some requests; let the API re-run a declined grade on its recommended fallback.
        if model == .opus { body["fallbacks"] = "default" }
        return body
    }

    public func judge(_ request: JudgeRequest, model: JudgeModel) async throws -> JudgeVerdict {
        try request.validate()
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw JudgeError.noAPIKey }

        var http = URLRequest(url: baseURL.appending(path: "v1/messages"))
        http.httpMethod = "POST"
        http.timeoutInterval = 180
        http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        http.setValue("application/json", forHTTPHeaderField: "content-type")
        if model == .opus { http.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        http.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(request, model: model))

        let started = ContinuousClock.now
        let (data, response) = try await session.data(for: http)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw JudgeError.api("No response from the Claude API.") }
        guard status == 200 else { throw JudgeError.api(Self.describeError(status: status, data: data)) }

        var verdict = try Self.parse(data, model: model)
        verdict.seconds = (ContinuousClock.now - started).seconds
        verdict.provider = .apiKey
        return verdict
    }

    /// Parses a Messages API response: checks for refusals, joins the text blocks and decodes the verdict.
    public static func parse(_ data: Data, model: JudgeModel) throws -> JudgeVerdict {
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            struct Usage: Decodable { let input_tokens: Int?; let output_tokens: Int? }
            struct StopDetails: Decodable { let category: String?; let explanation: String? }
            let content: [Block]
            let stop_reason: String?
            let stop_details: StopDetails?
            let usage: Usage?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw JudgeError.badOutput("unexpected API response")
        }
        if response.stop_reason == "refusal" {
            throw JudgeError.refused(response.stop_details?.explanation ?? response.stop_details?.category ?? "no reason given")
        }
        if response.stop_reason == "max_tokens" {
            throw JudgeError.badOutput("the verdict was cut off (max_tokens)")
        }
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard var verdict = try? JSONDecoder().decode(JudgeVerdict.self, from: Data(text.utf8)) else {
            throw JudgeError.badOutput(String(text.prefix(200)))
        }
        verdict.model = model
        if let input = response.usage?.input_tokens, let output = response.usage?.output_tokens {
            let price = model.pricePerMillion
            verdict.costUsd = (Double(input) * price.input + Double(output) * price.output) / 1_000_000
        }
        return JudgePrompt.normalised(verdict)
    }

    static func describeError(status: Int, data: Data) -> String {
        struct ErrorBody: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
        switch status {
        case 401: return "The Anthropic API key was rejected. Check it in Settings → Claude."
        case 429: return "Rate limited by the Claude API. Wait a moment and try again."
        case 529, 500...599: return "The Claude API is temporarily unavailable (\(status)). Try again shortly."
        default: return "Claude API error \(status): \(message ?? HTTPURLResponse.localizedString(forStatusCode: status))"
        }
    }
}
