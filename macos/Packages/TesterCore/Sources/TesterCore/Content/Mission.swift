import Foundation

/// A guided exercise teaching one category of chatbot bug.
public struct Mission: Codable, Sendable, Identifiable, Equatable {
    public struct Setup: Codable, Sendable, Equatable {
        public struct Settings: Codable, Sendable, Equatable {
            public let temperature: Double?
            public let seed: Int?
        }

        public enum Destination: String, Codable, Sendable {
            case bot, tests, judge
        }

        public let systemPrompt: String?
        public let settings: Settings?
        public let goTo: Destination?

        /// e.g. "fills in the system prompt, sets temperature 0, seed 42"
        public var summary: String {
            var parts: [String] = []
            if systemPrompt != nil { parts.append("fills in the system prompt") }
            if let settings {
                let values = [settings.temperature.map { "temperature \($0.formatted())" }, settings.seed.map { "seed \($0)" }].compactMap { $0 }
                if !values.isEmpty { parts.append("sets " + values.joined(separator: ", ")) }
            }
            switch goTo {
            case .bot: parts.append("switches to Target bots")
            case .tests: parts.append("opens the Test cases tab")
            case .judge: parts.append("opens the LLM-as-a-judge tab")
            case nil: break
            }
            return parts.joined(separator: ", ")
        }
    }

    public let id: String
    public let category: String
    public let title: String
    public let goal: String
    public let setup: Setup?
    public let prompts: [String]
    public let hints: [String]
    public let bug: String
    public let realWorld: String
}

extension Content {
    public static let missions: [Mission] = load("missions")
}
