import Foundation

/// One check on a reply. The JSON shape matches the web app's `data/testcases.json`.
public struct Assertion: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case contains
        case notContains = "not_contains"
        case regex
        case maxLength = "max_length"
        case minLength = "min_length"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .contains: "Contains"
            case .notContains: "Doesn't contain"
            case .regex: "Matches regex"
            case .maxLength: "Max length (chars)"
            case .minLength: "Min length (chars)"
            }
        }

        var isLength: Bool { self == .maxLength || self == .minLength }
    }

    public var type: Kind
    public var value: String
    public var caseSensitive: Bool

    public init(type: Kind = .contains, value: String = "", caseSensitive: Bool = false) {
        self.type = type
        self.value = value
        self.caseSensitive = caseSensitive
    }

    // Older exports may omit caseSensitive.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(Kind.self, forKey: .type)
        value = try c.decode(String.self, forKey: .value)
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
    }

    /// e.g. `Contains "Paris"`, `Max length (chars) 600`
    public var summary: String {
        let shown = type.isLength ? value : "\"\(value)\""
        return "\(type.label) \(shown)\(caseSensitive ? " (case-sensitive)" : "")"
    }

    public struct Result: Sendable, Equatable {
        public let assertion: Assertion
        public let pass: Bool
        public let detail: String?
    }

    public func check(_ reply: String) -> Result {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        switch type {
        case .contains:
            return Result(assertion: self, pass: text.range(of: value, options: options) != nil, detail: nil)
        case .notContains:
            return Result(assertion: self, pass: text.range(of: value, options: options) == nil, detail: nil)
        case .regex:
            do {
                let regex = try NSRegularExpression(pattern: value, options: caseSensitive ? [] : [.caseInsensitive])
                let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                return Result(assertion: self, pass: found, detail: nil)
            } catch {
                return Result(assertion: self, pass: false, detail: "Invalid regex")
            }
        case .maxLength, .minLength:
            guard let limit = Int(value.trimmingCharacters(in: .whitespaces)) else {
                return Result(assertion: self, pass: false, detail: "Not a number")
            }
            let pass = type == .maxLength ? text.count <= limit : text.count >= limit
            return Result(assertion: self, pass: pass, detail: "\(text.count) chars")
        }
    }
}
