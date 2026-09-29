import Foundation

public struct ChatMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// Generation settings. `seed` and `maxTokens` are nil for "random" / "no limit".
public struct ChatOptions: Sendable, Equatable, Codable {
    public var temperature: Double
    public var seed: Int?
    public var maxTokens: Int?

    public init(temperature: Double = 0.8, seed: Int? = nil, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.seed = seed
        self.maxTokens = maxTokens
    }

    /// e.g. "temp 0.8 · seed random" or "temp 0 · seed 42 · max 256 tokens"
    public var summary: String {
        var parts = ["temp \(temperature.formatted(.number.precision(.fractionLength(0...1))))"]
        parts.append(seed.map { "seed \($0)" } ?? "seed random")
        if let maxTokens { parts.append("max \(maxTokens) tokens") }
        return parts.joined(separator: " · ")
    }
}

public struct ChatStats: Sendable, Equatable {
    public var evalCount: Int?
    public var evalDurationNanos: Int?

    public init(evalCount: Int? = nil, evalDurationNanos: Int? = nil) {
        self.evalCount = evalCount
        self.evalDurationNanos = evalDurationNanos
    }

    public var tokensPerSecond: Double? {
        guard let evalCount, let evalDurationNanos, evalDurationNanos > 0 else { return nil }
        return Double(evalCount) / (Double(evalDurationNanos) / 1_000_000_000)
    }
}

public enum ChatEvent: Sendable, Equatable {
    /// A new piece of reply text (append it to what you have so far).
    case token(String)
    case done(ChatStats)
}

/// Prepends the system prompt, if any, to the conversation.
public func buildMessages(systemPrompt: String, conversation: [ChatMessage]) -> [ChatMessage] {
    let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? conversation : [ChatMessage(role: .system, content: trimmed)] + conversation
}

/// How many genuinely different answers a set of re-runs produced (ignoring surrounding whitespace).
public func uniqueAnswerCount(_ replies: [String]) -> Int {
    Set(replies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).count
}
