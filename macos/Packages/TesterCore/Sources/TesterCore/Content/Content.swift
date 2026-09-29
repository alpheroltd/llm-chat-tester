import Foundation

public struct RubricPreset: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let rubric: String
}

public struct JudgeExercise: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let rubric: String
    public let question: String
    public let systemPrompt: String
    public let reply: String
    /// What a careful human grader would say: "pass" or "fail".
    public let expected: JudgeVerdict.Outcome
    public let lesson: String
}

/// Learning content bundled with the app. It's exported from the web app's data files, so both stay in sync.
public enum Content {
    public static let rubricPresets: [RubricPreset] = load("rubric-presets")
    public static let judgeExercises: [JudgeExercise] = load("judge-exercises")
    public static let seedTestCases: [TestCase] = load("testcases.seed")
    public static let categories: [String] = load("categories")

    static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            fatalError("Missing bundled resource \(name).json")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Bundled resource \(name).json is invalid: \(error)")
        }
    }
}
