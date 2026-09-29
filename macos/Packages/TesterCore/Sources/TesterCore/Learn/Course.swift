import Foundation

/// The Learn tab's course: modules of lessons, a glossary and cheat sheets.
/// Everything is plain JSON + Markdown in `LearnContent/` so the QA team can edit it without Swift
/// (see macos/CONTENT_GUIDE.md).
public struct Course: Codable, Sendable, Equatable {
    public struct Module: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let summary: String
        public let lessons: [String]
    }

    public let title: String
    public let modules: [Module]
}

public struct PracticeLink: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// A mission from missions.json (opens Chat in Missions mode).
        case mission
        /// A target bot level such as "shopbot-1" (opens Chat in Target bots mode).
        case bot
        /// A "Judge the judge" exercise (opens the LLM-as-a-judge tab with it loaded).
        case judgeExercise
        case testCases
        case judge
        case freeChat
    }

    public let kind: Kind
    public let id: String?
    public let label: String
}

public struct QuizItem: Codable, Sendable, Equatable, Hashable {
    public let question: String
    public let options: [String]
    /// Index into `options` of the correct answer.
    public let answer: Int
    public let explanation: String
}

public struct Lesson: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable { case draft, reviewed }

    public let id: String
    public let title: String
    public let summary: String
    public let minutes: Int
    public let status: Status
    public let keyTerms: [String]
    public let practice: [PracticeLink]
    public let quiz: [QuizItem]
}

public struct GlossaryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let term: String
    public let definition: String
    public let seeAlso: [String]
}

public struct CheatSheet: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
}

/// Loads and holds the whole course from a content folder.
public struct LearnLibrary: Sendable {
    public let directory: URL
    public let course: Course
    public let lessons: [String: Lesson]
    public let glossary: [GlossaryEntry]
    public let cheatSheets: [CheatSheet]

    public enum LoadError: LocalizedError {
        case file(String, any Error)
        public var errorDescription: String? {
            switch self {
            case .file(let path, let error): "\(path): \(error.localizedDescription)"
            }
        }
    }

    public init(directory: URL) throws {
        self.directory = directory
        func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
            do {
                return try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appending(path: path)))
            } catch {
                throw LoadError.file(path, error)
            }
        }
        course = try decode(Course.self, "course.json")
        glossary = try decode([GlossaryEntry].self, "glossary.json")
        cheatSheets = try decode([CheatSheet].self, "cheatsheets/index.json")
        var lessons: [String: Lesson] = [:]
        for id in course.modules.flatMap(\.lessons) {
            if let lesson = try? decode(Lesson.self, "lessons/\(id).json") { lessons[id] = lesson }
        }
        self.lessons = lessons
    }

    /// Lessons in course order.
    public var orderedLessons: [Lesson] { course.modules.flatMap(\.lessons).compactMap { lessons[$0] } }

    public func body(ofLesson id: String) -> String {
        (try? String(contentsOf: directory.appending(path: "lessons/\(id).md"), encoding: .utf8)) ?? ""
    }

    public func body(ofCheatSheet id: String) -> String {
        (try? String(contentsOf: directory.appending(path: "cheatsheets/\(id).md"), encoding: .utf8)) ?? ""
    }

    /// Resolves an image path used in lesson Markdown, e.g. "images/tokens.png".
    public func imageURL(_ path: String) -> URL { directory.appending(path: path) }

    public func glossaryEntry(_ id: String) -> GlossaryEntry? { glossary.first { $0.id == id } }

    public func lesson(after id: String) -> Lesson? {
        let order = orderedLessons
        guard let index = order.firstIndex(where: { $0.id == id }), index + 1 < order.count else { return nil }
        return order[index + 1]
    }
}

extension Content {
    /// The bundled course.
    public static let learnDirectory: URL = {
        guard let url = Bundle.module.url(forResource: "LearnContent", withExtension: nil) else {
            fatalError("Missing bundled LearnContent folder")
        }
        return url
    }()

    public static let learn: LearnLibrary = {
        do {
            return try LearnLibrary(directory: learnDirectory)
        } catch {
            fatalError("Bundled Learn content is invalid: \(error.localizedDescription)")
        }
    }()
}
