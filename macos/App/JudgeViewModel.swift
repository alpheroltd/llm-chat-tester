import Foundation
import Observation
import TesterCore

struct JudgeCard: Identifiable, Equatable {
    enum State: Equatable {
        case pending
        case done(JudgeVerdict)
        case failed(String)
    }
    let id = UUID()
    var title: String?
    var state: State
}

struct JudgeHistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let label: String
    let verdict: JudgeVerdict
}

struct ExerciseProgress: Codable, Equatable {
    var mine: JudgeVerdict.Outcome
    var myScore: Int?
    var judge: JudgeVerdict.Outcome
    var judgeScore: Int
    var expected: JudgeVerdict.Outcome
}

struct ExerciseComparison: Equatable {
    let exercise: JudgeExercise
    let mine: JudgeVerdict.Outcome
    let myScore: Int?
    let judge: JudgeVerdict
    var judgeRight: Bool { judge.verdict == exercise.expected }
    var youRight: Bool { mine == exercise.expected }
}

@MainActor @Observable
final class JudgeViewModel {
    // Form
    var presetID: String = ""
    var rubric = ""
    var question = ""
    var systemPrompt = ""
    var reply = ""

    var model: JudgeModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "judgeModel") }
    }
    var provider: JudgeProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "judgeProvider") }
    }

    // Exercises
    private(set) var activeExercise: JudgeExercise?
    var prediction: JudgeVerdict.Outcome?
    var predictedScore: Int?
    private(set) var progress: [String: ExerciseProgress]
    private(set) var comparison: ExerciseComparison?

    // Results
    private(set) var cards: [JudgeCard] = []
    private(set) var consistency: String?
    private(set) var history: [JudgeHistoryEntry] = []
    var errorMessage: String?
    private(set) var isJudging = false
    private(set) var isGenerating = false
    private var task: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        model = defaults.string(forKey: "judgeModel").flatMap(JudgeModel.init(rawValue:)) ?? .haiku
        provider = defaults.string(forKey: "judgeProvider").flatMap(JudgeProvider.init(rawValue:)) ?? .claudeCode
        progress = (defaults.data(forKey: "judgeExercises")).flatMap { try? JSONDecoder().decode([String: ExerciseProgress].self, from: $0) } ?? [:]
    }

    var isBusy: Bool { isJudging || isGenerating }
    var totalCost: Double { history.compactMap(\.verdict.costUsd).reduce(0, +) }

    // MARK: Rubric presets

    func applyPreset(_ id: String) {
        presetID = id
        if let preset = Content.rubricPresets.first(where: { $0.id == id }) { rubric = preset.rubric }
    }

    /// Editing the rubric by hand makes it a custom rubric.
    func rubricEdited() {
        if let preset = Content.rubricPresets.first(where: { $0.id == presetID }), preset.rubric != rubric { presetID = "" }
    }

    // MARK: Exercises

    func loadExercise(_ exercise: JudgeExercise) {
        activeExercise = exercise
        prediction = nil
        predictedScore = nil
        comparison = nil
        presetID = ""
        rubric = exercise.rubric
        question = exercise.question
        systemPrompt = exercise.systemPrompt
        reply = exercise.reply
        cards = []
        consistency = nil
        errorMessage = nil
    }

    func exitExercise() {
        activeExercise = nil
        comparison = nil
    }

    var exercisesDone: Int { Content.judgeExercises.filter { progress[$0.id] != nil }.count }
    var youRightCount: Int { progress.values.filter { $0.mine == $0.expected }.count }
    var judgeRightCount: Int { progress.values.filter { $0.judge == $0.expected }.count }

    private func record(_ exercise: JudgeExercise, verdict: JudgeVerdict) {
        guard let mine = prediction else { return }
        progress[exercise.id] = ExerciseProgress(mine: mine, myScore: predictedScore, judge: verdict.verdict, judgeScore: verdict.score, expected: exercise.expected)
        if let data = try? JSONEncoder().encode(progress) { UserDefaults.standard.set(data, forKey: "judgeExercises") }
        comparison = ExerciseComparison(exercise: exercise, mine: mine, myScore: predictedScore, judge: verdict)
    }

    // MARK: Generate a reply with the local model

    func generateReply(app: AppState) {
        errorMessage = nil
        guard !app.selectedModel.isEmpty else { errorMessage = "Select a local model in the sidebar first."; return }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { errorMessage = "Type a question first."; return }
        // Fall back to the sidebar's system prompt, and copy it in so the judge sees the same instructions.
        if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { systemPrompt = app.systemPrompt }
        let messages = buildMessages(systemPrompt: systemPrompt, conversation: [ChatMessage(role: .user, content: question)])
        let client = app.ollama, model = app.selectedModel, options = app.options
        reply = ""
        isGenerating = true
        task = Task { [weak self] in
            do {
                for try await event in client.streamChat(model: model, messages: messages, options: options) {
                    if case .token(let token) = event { self?.reply += token }
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isGenerating = false
        }
    }

    // MARK: Judging

    private func runner(app: AppState) -> any JudgeRunner {
        switch provider {
        case .claudeCode: ClaudeCodeJudge(cliPathOverride: app.claudePathOverride.isEmpty ? nil : app.claudePathOverride)
        case .apiKey: AnthropicAPIJudge(apiKey: KeychainStore.readAPIKey() ?? "")
        }
    }

    func judge(times: Int, app: AppState) {
        errorMessage = nil
        let request = JudgeRequest(rubric: rubric, question: question, systemPrompt: systemPrompt, reply: reply)
        do { try request.validate() } catch { errorMessage = error.localizedDescription; return }
        if activeExercise != nil && prediction == nil {
            errorMessage = "Make your own prediction first (Pass or Fail), then judge."
            return
        }
        let label = activeExercise?.title ?? Content.rubricPresets.first { $0.id == presetID }?.name ?? "Custom rubric"
        let exercise = activeExercise
        let runner = runner(app: app), model = model
        cards = (0..<times).map { JudgeCard(title: times > 1 ? "Run \($0 + 1)" : nil, state: .pending) }
        consistency = nil
        comparison = nil
        isJudging = true

        task = Task { [weak self] in
            var verdicts: [JudgeVerdict] = []
            for index in 0..<times {
                guard let self, !Task.isCancelled else { break }
                do {
                    let verdict = try await runner.judge(request, model: model)
                    try Task.checkCancellation()
                    verdicts.append(verdict)
                    self.cards[index].state = .done(verdict)
                    self.history.insert(JudgeHistoryEntry(time: Date(), label: label, verdict: verdict), at: 0)
                } catch is CancellationError {
                    self.cards[index].state = .failed("Stopped.")
                    break
                } catch {
                    self.cards[index].state = .failed(error.localizedDescription)
                }
            }
            guard let self else { return }
            self.cards.removeAll { $0.state == .pending }
            if verdicts.count > 1 { self.consistency = Self.consistencySummary(verdicts) }
            if let exercise, let first = verdicts.first { self.record(exercise, verdict: first) }
            self.isJudging = false
        }
    }

    func stop() { task?.cancel() }

    static func consistencySummary(_ verdicts: [JudgeVerdict]) -> String {
        let passes = verdicts.filter { $0.verdict == .pass }.count
        let majority = max(passes, verdicts.count - passes)
        let scores = verdicts.map(\.score)
        let spread = (scores.max() ?? 0) - (scores.min() ?? 0)
        let base = "Verdict consistent \(majority)/\(verdicts.count) · scores \(scores.map(String.init).joined(separator: ", ")) (spread \(spread))"
        if majority < verdicts.count {
            return "⚠️ \(base). The judge disagreed with itself. Automated graders are non-deterministic too; use several runs or a tighter rubric."
        }
        return spread > 1 ? "\(base). Same verdict, but the scores moved a lot. Don't rely on exact scores." : "✅ \(base). Stable for this case."
    }
}
