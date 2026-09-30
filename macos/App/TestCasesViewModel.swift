import Foundation
import Observation
import TesterCore

struct CaseResultState: Equatable {
    var runs: [CaseRun] = []
    var total: Int
    var isRunning = true
    var status: CaseStatus? { isRunning ? nil : CaseStatus(runs: runs) }
}

/// Saved test cases (a JSON file in Application Support) and the suite runner.
@MainActor @Observable
final class TestCasesViewModel {
    private(set) var cases: [TestCase] = []
    private(set) var results: [String: CaseResultState] = [:]
    private(set) var isRunning = false
    var summary: String?
    var errorMessage: String?
    /// The case being edited in the editor sheet (nil = sheet closed).
    var editing: TestCase?

    var runsPerCase: Int {
        didSet { UserDefaults.standard.set(runsPerCase, forKey: "runsPerCase") }
    }

    private let storeURL: URL
    private var savingBlocked = false
    private var runTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        runsPerCase = max(1, defaults.integer(forKey: "runsPerCase"))
        // Launch argument `-testCasesPath <file>` lets UI tests use a scratch file.
        if let override = defaults.string(forKey: "testCasesPath"), !override.isEmpty {
            storeURL = URL(fileURLWithPath: override)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            storeURL = support.appending(path: "LLM Chat Tester/testcases.json")
        }
        load()
    }

    // MARK: Storage

    private func load() {
        do {
            cases = try TestCase.decodeSuite(from: Data(contentsOf: storeURL))
        } catch CocoaError.fileReadNoSuchFile {
            cases = Content.seedTestCases // first launch: start with the examples
            persist()
        } catch {
            cases = []
            // Saving over an unreadable file would delete every case in it, so move it aside first.
            let backup = storeURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            if (try? FileManager.default.moveItem(at: storeURL, to: backup)) != nil {
                errorMessage = "Couldn't read your saved test cases, so they were moved to \(backup.path) and the list starts empty. (\(error.localizedDescription))"
            } else {
                savingBlocked = true
                errorMessage = "Couldn't read saved test cases (\(storeURL.path)), so changes won't be saved until it's fixed: \(error.localizedDescription)"
            }
        }
    }

    private func persist() {
        guard !savingBlocked else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try TestCase.encodeSuite(cases).write(to: storeURL, options: .atomic)
        } catch {
            errorMessage = "Couldn't save test cases: \(error.localizedDescription)"
        }
    }

    // MARK: Editing

    func newCase(prompt: String = "", systemPrompt: String = "", botId: String = "") {
        editing = TestCase(prompt: prompt, systemPrompt: systemPrompt, botId: botId)
    }

    func edit(_ testCase: TestCase) { editing = testCase }

    /// Saves the edited case. Returns an error message instead if it isn't valid.
    func save(_ testCase: TestCase) -> String? {
        if let problem = testCase.validationError { return problem }
        let clean = testCase.cleaned
        if let index = cases.firstIndex(where: { $0.id == clean.id }) {
            cases[index] = clean
        } else {
            cases.append(clean)
        }
        results[clean.id] = nil
        persist()
        editing = nil
        return nil
    }

    func delete(_ testCase: TestCase) {
        cases.removeAll { $0.id == testCase.id }
        results[testCase.id] = nil
        persist()
    }

    // MARK: Import / export

    func exportData() throws -> Data { try TestCase.encodeSuite(cases) }

    /// Adds cases from a suite file; cases with the same id are replaced. Returns how many were imported.
    @discardableResult
    func importSuite(from url: URL) -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let incoming = try TestCase.decodeSuite(from: Data(contentsOf: url))
            for testCase in incoming {
                if let index = cases.firstIndex(where: { $0.id == testCase.id }) { cases[index] = testCase } else { cases.append(testCase) }
            }
            persist()
            summary = "Imported \(incoming.count) test case(s) from \(url.lastPathComponent)."
            return incoming.count
        } catch {
            errorMessage = "Couldn't import \(url.lastPathComponent): it isn't a test-case suite (\(error.localizedDescription))."
            return 0
        }
    }

    // MARK: Running

    func run(_ list: [TestCase], app: AppState) {
        guard !isRunning, !list.isEmpty else { return }
        guard !app.selectedModel.isEmpty else {
            summary = "Select a model first."
            return
        }
        let model = app.selectedModel, options = app.options, client = app.ollama
        let runs = max(1, min(runsPerCase, 10))
        isRunning = true
        summary = nil
        let started = ContinuousClock.now

        runTask = Task { [weak self] in
            var stopped = false
            for testCase in list {
                guard let self, !Task.isCancelled else { stopped = true; break }
                self.results[testCase.id] = CaseResultState(total: runs)
                for _ in 0..<runs {
                    do {
                        let run = try await SuiteRunner.run(testCase, model: model, options: options, client: client)
                        self.results[testCase.id]?.runs.append(run)
                    } catch {
                        stopped = true
                        break
                    }
                }
                if self.results[testCase.id]?.runs.isEmpty == true { self.results[testCase.id] = nil } else { self.results[testCase.id]?.isRunning = false }
                if stopped { break }
            }
            guard let self else { return }
            let statuses = list.compactMap { self.results[$0.id]?.status }
            let seconds = (ContinuousClock.now - started)
            let secs = Double(seconds.components.seconds) + Double(seconds.components.attoseconds) / 1e18
            self.summary = (stopped ? "Stopped · " : "") + SuiteRunner.summary(statuses)
                + " · \(model) · \(options.summary) · \(runs) run(s) per case · " + String(format: "%.1fs", secs)
            self.isRunning = false
        }
    }

    func stop() { runTask?.cancel() }
}
