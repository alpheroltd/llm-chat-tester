import Foundation

/// A single-message test with checks. Suites are shared by exporting and importing this JSON.
public struct TestCase: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var prompt: String
    public var systemPrompt: String
    /// Empty string = talk to the model directly; otherwise a target bot id such as "shopbot-3".
    public var botId: String
    public var assertions: [Assertion]

    public init(id: String = UUID().uuidString, name: String = "", prompt: String = "", systemPrompt: String = "",
                botId: String = "", assertions: [Assertion] = [Assertion()]) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.botId = botId
        self.assertions = assertions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        botId = try c.decodeIfPresent(String.self, forKey: .botId) ?? ""
        assertions = try c.decode([Assertion].self, forKey: .assertions)
    }

    /// Problems that stop the case being saved, or nil if it's valid.
    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name and prompt are required."
        }
        if assertions.allSatisfy({ $0.value.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Add at least one check with a value."
        }
        return nil
    }

    /// A copy with blank checks removed and text trimmed, ready to save.
    public var cleaned: TestCase {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.systemPrompt = botId.isEmpty ? systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        copy.assertions = assertions.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        return copy
    }

    public static func decodeSuite(from data: Data) throws -> [TestCase] {
        try JSONDecoder().decode([TestCase].self, from: data)
    }

    public static func encodeSuite(_ cases: [TestCase]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(cases)
    }
}

/// One run of a test case.
public struct CaseRun: Sendable, Equatable {
    public var reply: String
    public var checks: [Assertion.Result]
    public var error: String?
    public var seconds: Double

    public init(reply: String, assertions: [Assertion], seconds: Double) {
        self.reply = reply
        self.checks = assertions.map { $0.check(reply) }
        self.error = nil
        self.seconds = seconds
    }

    public init(error: String, seconds: Double) {
        self.reply = ""
        self.checks = []
        self.error = error
        self.seconds = seconds
    }

    public var pass: Bool { error == nil && checks.allSatisfy(\.pass) }
}

public enum CaseStatus: String, Sendable {
    case pass, flaky, fail

    /// All runs pass → pass; none → fail; some → flaky.
    public init?(runs: [CaseRun]) {
        guard !runs.isEmpty else { return nil }
        let passed = runs.filter(\.pass).count
        self = passed == runs.count ? .pass : (passed == 0 ? .fail : .flaky)
    }
}
