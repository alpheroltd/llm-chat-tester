import Foundation

/// Checks a Learn content folder for mistakes an author could make, with messages that say how to fix them.
/// Run by the unit tests, so broken content fails `swift test` before it can ship.
public enum ContentLint {
    public static func problems(
        in directory: URL,
        missionIDs: Set<String> = Set(Content.missions.map(\.id)),
        botIDs: Set<String> = Set(BotEngine.bots.map(\.id)),
        exerciseIDs: Set<String> = Set(Content.judgeExercises.map(\.id))
    ) -> [String] {
        let library: LearnLibrary
        do {
            library = try LearnLibrary(directory: directory)
        } catch {
            return ["Couldn't load the course: \(error.localizedDescription)"]
        }
        let fm = FileManager.default
        var problems: [String] = []
        let glossaryIDs = Set(library.glossary.map(\.id))

        // Duplicate ids
        func duplicates(_ ids: [String]) -> [String] { Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.map(\.key).sorted() }
        for id in duplicates(library.course.modules.map(\.id)) { problems.append("course.json: module id \"\(id)\" is used more than once") }
        for id in duplicates(library.course.modules.flatMap(\.lessons)) { problems.append("course.json: lesson \"\(id)\" is listed more than once") }
        for id in duplicates(library.glossary.map(\.id)) { problems.append("glossary.json: term id \"\(id)\" is used more than once") }

        // Lessons
        for module in library.course.modules {
            if module.lessons.isEmpty { problems.append("course.json: module \"\(module.id)\" has no lessons") }
            for id in module.lessons {
                let jsonPath = "lessons/\(id).json"
                guard let lesson = library.lessons[id] else {
                    let exists = fm.fileExists(atPath: directory.appending(path: jsonPath).path)
                    problems.append(exists ? "\(jsonPath): isn't valid lesson JSON (check commas, quotes and required fields)" : "\(jsonPath): missing (listed in course.json module \"\(module.id)\")")
                    continue
                }
                let where_ = "lessons/\(id)"
                if lesson.id != id { problems.append("\(jsonPath): \"id\" is \"\(lesson.id)\" but the file is named \(id)") }
                let bodyPath = directory.appending(path: "\(where_).md")
                if !fm.fileExists(atPath: bodyPath.path) {
                    problems.append("\(where_).md: missing (every lesson needs a Markdown body)")
                } else {
                    for image in MarkdownParser.imagePaths(in: library.body(ofLesson: id)) where !fm.fileExists(atPath: library.imageURL(image).path) {
                        problems.append("\(where_).md: image \"\(image)\" not found in the content folder")
                    }
                }
                for term in lesson.keyTerms where !glossaryIDs.contains(term) {
                    problems.append("\(jsonPath): key term \"\(term)\" isn't in glossary.json")
                }
                for (i, link) in lesson.practice.enumerated() {
                    let label = "\(jsonPath): practice #\(i + 1) (\(link.label))"
                    switch link.kind {
                    case .mission: if !missionIDs.contains(link.id ?? "") { problems.append("\(label): no mission with id \"\(link.id ?? "")\"") }
                    case .bot: if !botIDs.contains(link.id ?? "") { problems.append("\(label): no bot with id \"\(link.id ?? "")\" (use shopbot-1 … shopbot-5)") }
                    case .judgeExercise: if !exerciseIDs.contains(link.id ?? "") { problems.append("\(label): no judge exercise with id \"\(link.id ?? "")\"") }
                    case .testCases, .judge, .freeChat: break
                    }
                }
                for (i, item) in lesson.quiz.enumerated() {
                    let label = "\(jsonPath): quiz question #\(i + 1)"
                    if item.options.count < 2 { problems.append("\(label): needs at least 2 options") }
                    if !item.options.indices.contains(item.answer) {
                        problems.append("\(label): \"answer\" is \(item.answer) but must be 0–\(max(item.options.count - 1, 0)) (0 = first option)")
                    }
                    if Set(item.options).count != item.options.count { problems.append("\(label): two options are identical") }
                }
                if lesson.minutes <= 0 { problems.append("\(jsonPath): \"minutes\" must be at least 1") }
            }
        }

        // Glossary cross-references
        for entry in library.glossary {
            for other in entry.seeAlso where !glossaryIDs.contains(other) {
                problems.append("glossary.json: \"\(entry.id)\" has seeAlso \"\(other)\", which isn't a term")
            }
        }

        // Cheat sheets
        for sheet in library.cheatSheets where !fm.fileExists(atPath: directory.appending(path: "cheatsheets/\(sheet.id).md").path) {
            problems.append("cheatsheets/\(sheet.id).md: missing (listed in cheatsheets/index.json)")
        }
        return problems
    }
}
