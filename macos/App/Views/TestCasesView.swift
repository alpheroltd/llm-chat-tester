import SwiftUI
import TesterCore
import UniformTypeIdentifiers

struct TestCasesView: View {
    @Environment(AppState.self) private var app
    @Environment(TestCasesViewModel.self) private var suite
    @State private var importing = false
    @State private var exporting = false
    @State private var pendingDelete: TestCase?

    var body: some View {
        @Bindable var suite = suite
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if let summary = suite.summary {
                Text(summary).font(.callout.bold()).padding(.horizontal, 16).padding(.bottom, 6)
                    .accessibilityIdentifier("tc-summary")
            }
            if let error = suite.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
            Text("Runs use the model and settings in the sidebar. Each test case sends one message and checks the reply. Set runs per case to 3+ to find flaky tests.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
            Divider()
            if suite.cases.isEmpty {
                ContentUnavailableView("No test cases yet", systemImage: "checklist",
                                       description: Text("Create one, import a suite, or use \"Save as test case\" under a message in Chat."))
            } else {
                List {
                    ForEach(suite.cases) { testCase in
                        TestCaseRow(testCase: testCase, onDelete: { pendingDelete = testCase })
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("tc-list")
            }
        }
        .sheet(item: $suite.editing) { testCase in
            TestCaseEditor(testCase: testCase)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { suite.importSuite(from: url) }
        }
        .fileExporter(isPresented: $exporting, document: SuiteDocument(data: (try? suite.exportData()) ?? Data()),
                      contentType: .json, defaultFilename: "testcases.json") { _ in }
        .confirmationDialog("Delete \"\(pendingDelete?.name ?? "")\"?", isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { if let tc = pendingDelete { suite.delete(tc) }; pendingDelete = nil }
        }
    }

    private var toolbar: some View {
        @Bindable var suite = suite
        return HStack(spacing: 10) {
            Button { suite.newCase() } label: { Label("New test case", systemImage: "plus") }
                .accessibilityIdentifier("tc-new")
            Stepper("Runs per case: \(suite.runsPerCase)", value: $suite.runsPerCase, in: 1...10)
                .fixedSize()
                .accessibilityIdentifier("tc-runs")
            if suite.isRunning {
                Button("Stop", action: suite.stop).accessibilityIdentifier("tc-stop")
                ProgressView().controlSize(.small)
            } else {
                Button { suite.run(suite.cases, app: app) } label: { Label("Run suite", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(suite.cases.isEmpty)
                    .accessibilityIdentifier("tc-run-suite")
            }
            Spacer()
            Button("Import…") { importing = true }.disabled(suite.isRunning)
            Button("Export…") { exporting = true }.disabled(suite.cases.isEmpty)
        }
        .padding(16)
    }
}

private struct TestCaseRow: View {
    @Environment(AppState.self) private var app
    @Environment(TestCasesViewModel.self) private var suite
    let testCase: TestCase
    let onDelete: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(testCase.name).font(.headline)
                    Text(target).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                badge
                Button("Run") { suite.run([testCase], app: app) }.disabled(suite.isRunning)
                Button("Edit") { suite.edit(testCase) }.disabled(suite.isRunning)
                Button("Delete", role: .destructive, action: onDelete).disabled(suite.isRunning)
            }
            .buttonStyle(.link)
            Text(verbatim: testCase.prompt).font(.callout).lineLimit(2).foregroundStyle(.primary.opacity(0.85))
            HStack(spacing: 6) {
                ForEach(testCase.assertions, id: \.self) { a in
                    Text(a.summary).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            if let result = suite.results[testCase.id], !result.runs.isEmpty {
                DisclosureGroup("Details", isExpanded: $expanded) {
                    ForEach(Array(result.runs.enumerated()), id: \.offset) { index, run in
                        RunDetail(index: index, run: run)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tc-row")
    }

    private var target: String {
        if !testCase.botId.isEmpty { return BotEngine.bot(id: testCase.botId)?.name ?? testCase.botId }
        return testCase.systemPrompt.isEmpty ? "Model directly" : "Custom system prompt"
    }

    @ViewBuilder private var badge: some View {
        if let result = suite.results[testCase.id] {
            if result.isRunning {
                Text("⏳ \(result.runs.count)/\(result.total)").foregroundStyle(.secondary)
            } else if let status = result.status {
                let passed = result.runs.filter(\.pass).count
                let label = switch status { case .pass: "✅ Pass"; case .fail: "❌ Fail"; case .flaky: "⚠️ Flaky" }
                Text(result.runs.count > 1 ? "\(label) \(passed)/\(result.runs.count)" : label)
                    .bold()
                    .foregroundStyle(status == .pass ? .green : status == .fail ? .red : .orange)
                    .accessibilityIdentifier("tc-status")
            }
        }
    }
}

private struct RunDetail: View {
    let index: Int
    let run: CaseRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Run \(index + 1) · \(String(format: "%.2fs", run.seconds))").foregroundStyle(.secondary)
            if let error = run.error {
                Text(error).foregroundStyle(.red)
            } else {
                ForEach(Array(run.checks.enumerated()), id: \.offset) { _, check in
                    Text("\(check.pass ? "✅" : "❌") \(check.assertion.summary)\(check.detail.map { " (\($0))" } ?? "")")
                }
                Text(verbatim: run.reply)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }
}

struct TestCaseEditor: View {
    @Environment(TestCasesViewModel.self) private var suite
    @Environment(\.dismiss) private var dismiss
    @State var testCase: TestCase
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $testCase.name, prompt: Text("e.g. States the returns policy"))
                        .accessibilityIdentifier("tc-name")
                    Picker("Target", selection: $testCase.botId) {
                        Text("Model directly").tag("")
                        ForEach(BotEngine.bots) { Text($0.name).tag($0.id) }
                    }
                    .accessibilityIdentifier("tc-target")
                    if testCase.botId.isEmpty {
                        LabeledContent("System prompt") {
                            TextEditor(text: $testCase.systemPrompt).frame(height: 60)
                                .accessibilityIdentifier("tc-system")
                        }
                    }
                    LabeledContent("Prompt") {
                        TextEditor(text: $testCase.prompt).frame(height: 60)
                            .accessibilityIdentifier("tc-prompt")
                    }
                }
                Section {
                    ForEach($testCase.assertions.indices, id: \.self) { index in
                        HStack {
                            Picker("Check", selection: $testCase.assertions[index].type) {
                                ForEach(Assertion.Kind.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                            TextField("value", text: $testCase.assertions[index].value)
                                .accessibilityIdentifier("tc-check-value")
                            Toggle("case-sensitive", isOn: $testCase.assertions[index].caseSensitive)
                                .toggleStyle(.checkbox)
                            Button(role: .destructive) { testCase.assertions.remove(at: index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove check")
                        }
                    }
                    Button { testCase.assertions.append(Assertion()) } label: { Label("Add check", systemImage: "plus") }
                        .accessibilityIdentifier("tc-add-check")
                } header: {
                    Text("Checks (all must pass)")
                } footer: {
                    Text("Tip: check for key facts (\"contains 30\") rather than exact sentences. Exact wording changes from run to run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let error { Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("tc-error") }
                Spacer()
                Button("Cancel") { suite.editing = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    error = suite.save(testCase)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("tc-save")
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
    }
}

/// Wraps suite JSON for the Export… save panel.
struct SuiteDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
