import Foundation
import Observation
import TesterCore

/// Learn tab state: what's open, and the learner's progress (saved on this Mac only).
@MainActor @Observable
final class LearnViewModel {
    enum Item: Hashable {
        case lesson(String)
        case glossary
        case cheatSheet(String)
    }

    let library = Content.learn
    var selection: Item {
        didSet { if case .lesson(let id) = selection { UserDefaults.standard.set(id, forKey: "learnLesson") } }
    }
    private(set) var lessonsRead: Set<String> {
        didSet { UserDefaults.standard.set(Array(lessonsRead), forKey: "learnLessonsRead") }
    }
    /// Best quiz score per lesson (number correct).
    private(set) var bestScores: [String: Int] {
        didSet { UserDefaults.standard.set(bestScores, forKey: "learnQuizScores") }
    }

    init() {
        let defaults = UserDefaults.standard
        lessonsRead = Set(defaults.stringArray(forKey: "learnLessonsRead") ?? [])
        bestScores = (defaults.dictionary(forKey: "learnQuizScores") as? [String: Int]) ?? [:]
        let last = defaults.string(forKey: "learnLesson").flatMap { id in Content.learn.lessons[id] != nil ? id : nil }
        selection = .lesson(last ?? Content.learn.orderedLessons.first?.id ?? "")
    }

    var lessons: [Lesson] { library.orderedLessons }

    func markRead(_ id: String, _ read: Bool = true) {
        if read { lessonsRead.insert(id) } else { lessonsRead.remove(id) }
    }

    func recordQuiz(_ lesson: Lesson, correct: Int) {
        bestScores[lesson.id] = max(bestScores[lesson.id] ?? 0, correct)
    }

    /// e.g. "3 of 9 lessons read · quiz average 75%"
    var progressSummary: String {
        let read = "\(lessonsRead.intersection(lessons.map(\.id)).count) of \(lessons.count) lessons read"
        let quizzed = lessons.filter { !$0.quiz.isEmpty && bestScores[$0.id] != nil }
        guard !quizzed.isEmpty else { return read }
        let correct = quizzed.reduce(0) { $0 + (bestScores[$1.id] ?? 0) }
        let total = quizzed.reduce(0) { $0 + $1.quiz.count }
        return "\(read) · quiz average \(Int((Double(correct) / Double(total) * 100).rounded()))%"
    }

    // MARK: Practice

    /// Opens the practice a lesson links to: a mission or bot level in Chat, a judge exercise, or a tab.
    func practice(_ link: PracticeLink, app: AppState, chat: ChatViewModel, judge: JudgeViewModel) {
        switch link.kind {
        case .mission:
            guard let id = link.id else { return }
            chat.clear()
            app.winBannerBotID = nil
            app.mode = .missions
            app.selectedMissionID = id
            app.tab = .chat
        case .bot:
            guard let id = link.id else { return }
            chat.clear()
            app.winBannerBotID = nil
            app.mode = .targetBots
            app.selectedBotID = id
            app.tab = .chat
        case .judgeExercise:
            guard let exercise = Content.judgeExercises.first(where: { $0.id == link.id }) else { return }
            judge.loadExercise(exercise)
            app.tab = .judge
        case .testCases:
            app.tab = .testCases
        case .judge:
            app.tab = .judge
        case .freeChat:
            if app.mode != .free {
                chat.clear()
                app.mode = .free
            }
            app.tab = .chat
        }
    }

    /// Whether the linked practice has been done, from the progress the other tabs already keep.
    func isDone(_ link: PracticeLink, app: AppState, judge: JudgeViewModel) -> Bool {
        guard let id = link.id else { return false }
        switch link.kind {
        case .mission: return app.completedMissions.contains(id)
        case .bot: return app.beatenLevels.contains(id)
        case .judgeExercise: return judge.progress[id] != nil
        default: return false
        }
    }
}
