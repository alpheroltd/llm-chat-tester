import SwiftUI
import TesterCore

struct JudgeView: View {
    @Environment(AppState.self) private var app
    @Environment(JudgeViewModel.self) private var judge

    var body: some View {
        @Bindable var judge = judge
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                ExercisesCard()
                card {
                    HStack {
                        Text("1. Rubric").font(.headline)
                        Spacer()
                        Picker("Preset", selection: Binding(get: { judge.presetID }, set: { judge.applyPreset($0) })) {
                            Text("Custom rubric").tag("")
                            ForEach(Content.rubricPresets) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("judge-preset")
                    }
                    TextEditor(text: $judge.rubric)
                        .frame(minHeight: 80)
                        .onChange(of: judge.rubric) { judge.rubricEdited() }
                        .accessibilityIdentifier("judge-rubric")
                    Text("Write one criterion per line. Every criterion must be met to pass. Vague rubrics give vague verdicts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                card {
                    Text("2. What to judge").font(.headline)
                    field("Bot's system prompt (optional)", text: $judge.systemPrompt, height: 50, id: "judge-system")
                    Text("The chatbot's instructions. Used when generating a reply, and shown to the judge. If left empty, the sidebar's system prompt is used.")
                        .font(.caption).foregroundStyle(.secondary)
                    field("Question", text: $judge.question, height: 40, id: "judge-question")
                    field("Reply", text: $judge.reply, height: 100, id: "judge-reply")
                    HStack {
                        Button { judge.generateReply(app: app) } label: { Label("Generate reply with local model", systemImage: "sparkles") }
                            .disabled(judge.isBusy)
                            .accessibilityIdentifier("judge-generate")
                        if judge.isGenerating { ProgressView().controlSize(.small) }
                        Text("Uses \(app.selectedModel.isEmpty ? "the sidebar model" : app.selectedModel) and the sidebar settings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                actions
                if let error = judge.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        .accessibilityIdentifier("judge-error")
                }
                if let comparison = judge.comparison { ComparisonCard(comparison: comparison) }
                if let consistency = judge.consistency {
                    Text(consistency).font(.callout.bold()).accessibilityIdentifier("judge-summary")
                }
                if !judge.cards.isEmpty {
                    // Not a lazy grid: 1-3 cards, and lazy items stay out of the accessibility tree until scrolled to.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(judge.cards) { VerdictCard(card: $0).frame(minWidth: 240) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(judge.cards) { VerdictCard(card: $0) }
                        }
                    }
                }
                HistoryCard()
            }
            .padding(16)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var intro: some View {
        @Bindable var judge = judge
        return card {
            Text("LLM-as-a-judge").font(.title2.bold())
            Text("An LLM judge grades a chatbot's reply against a rubric you write. Teams use this to test chatbots at scale, because no human can read every reply. Judges make mistakes too, so part of your job is learning when to trust them.")
            // Wraps instead of forcing the window wider at narrow sizes.
            FlowLayout(spacing: 12) {
                Picker("Judge", selection: $judge.model) {
                    ForEach(JudgeModel.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
                .accessibilityIdentifier("judge-model")
                Picker("Using", selection: $judge.provider) {
                    ForEach(JudgeProvider.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
                .accessibilityIdentifier("judge-provider")
                if judge.provider == .claudeCode {
                    StatusBadge(status: app.claudeStatus).accessibilityIdentifier("judge-status")
                } else {
                    StatusBadge(status: app.hasAPIKey ? .ok("API key saved") : .problem("No API key: add one in Settings (⌘,)"))
                }
            }
            Text("The judge runs on Claude, so the text you judge is sent to Anthropic. The chatbot being tested still runs locally.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button { judge.judge(times: 1, app: app) } label: { Label("Judge", systemImage: "scalemass") }
                .buttonStyle(.borderedProminent)
                .disabled(judge.isBusy)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityIdentifier("judge-run")
            Button { judge.judge(times: 3, app: app) } label: { Label("Judge ×3", systemImage: "scalemass") }
                .disabled(judge.isBusy)
                .accessibilityIdentifier("judge-run-3")
            if judge.isBusy {
                Button("Stop", action: judge.stop).accessibilityIdentifier("judge-stop")
                ProgressView().controlSize(.small)
                Text(judge.isJudging ? "Judging… (\(judge.model.rawValue) usually takes 5–15s)" : "Generating…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, height: CGFloat, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            TextEditor(text: text)
                .frame(minHeight: height)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .accessibilityIdentifier(id)
        }
    }
}

/// A rounded panel, like the web app's cards.
func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8, content: content)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
}

private struct ExercisesCard: View {
    @Environment(JudgeViewModel.self) private var judge
    @State private var expanded = true

    var body: some View {
        @Bindable var judge = judge
        card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each exercise loads a tricky reply. Decide your own verdict first, then see whether the judge agrees with you and with the expected answer.")
                        .font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(Content.judgeExercises) { exercise in
                            let active = judge.activeExercise?.id == exercise.id
                            Button((judge.progress[exercise.id] != nil ? "✓ " : "") + exercise.title) { judge.loadExercise(exercise) }
                                .buttonStyle(.bordered)
                                .tint(active ? .accentColor : nil)
                                .accessibilityIdentifier("exercise-\(exercise.id)")
                        }
                    }
                    if let exercise = judge.activeExercise {
                        VStack(alignment: .leading, spacing: 8) {
                            (Text("Exercise: \(exercise.title). ").bold() + Text("Read the rubric and reply below. What should the verdict be?"))
                            HStack {
                                Picker("Your verdict", selection: $judge.prediction) {
                                    Text("Choose…").tag(JudgeVerdict.Outcome?.none)
                                    Text("✅ Pass").tag(JudgeVerdict.Outcome?.some(.pass))
                                    Text("❌ Fail").tag(JudgeVerdict.Outcome?.some(.fail))
                                }
                                .pickerStyle(.segmented)
                                .fixedSize()
                                .accessibilityIdentifier("predict-verdict")
                                Picker("Score", selection: $judge.predictedScore) {
                                    Text("Score (optional)").tag(Int?.none)
                                    ForEach([5, 4, 3, 2, 1], id: \.self) { Text("\($0)/5").tag(Int?.some($0)) }
                                }
                                .fixedSize()
                                .accessibilityIdentifier("predict-score")
                                Button("Exit exercise", action: judge.exitExercise).buttonStyle(.link)
                            }
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("predict-panel")
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Judge the judge").font(.headline)
                    Text(progressText).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("exercise-progress")
                }
            }
        }
    }

    private var progressText: String {
        let done = judge.exercisesDone, total = Content.judgeExercises.count
        guard done > 0 else { return "\(done) of \(total) done" }
        return "\(done) of \(total) done · you were right \(judge.youRightCount)/\(done) · the judge was right \(judge.judgeRightCount)/\(done)"
    }
}

private struct ComparisonCard: View {
    let comparison: ExerciseComparison

    var body: some View {
        card {
            Text("You vs the judge").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow { Text(""); Text("Verdict").bold(); Text("Score").bold(); Text("") }
                GridRow {
                    Text("You"); Text(comparison.mine.rawValue.uppercased())
                    Text(comparison.myScore.map { "\($0)/5" } ?? "n/a"); Text(comparison.youRight ? "✅" : "❌")
                }
                GridRow {
                    Text("Judge"); Text(comparison.judge.verdict.rawValue.uppercased())
                    Text("\(comparison.judge.score)/5"); Text(comparison.judgeRight ? "✅" : "❌")
                }
                GridRow { Text("Expected"); Text(comparison.exercise.expected.rawValue.uppercased()); Text(""); Text("") }
            }
            (Text(comparison.judgeRight ? "The judge got this one right. " : "⚠️ The judge got this one wrong. ").bold()
                + Text(comparison.exercise.lesson))
            if !comparison.judgeRight {
                Text("A judge mistake like this is a finding in itself. On a real project you'd tighten the rubric, try a stronger judge model, or keep a human review step for this kind of case.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("judge-compare")
    }
}

private struct VerdictCard: View {
    let card: JudgeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = card.title { Text(title).font(.caption).foregroundStyle(.secondary) }
            switch card.state {
            case .pending:
                HStack { ProgressView().controlSize(.small); Text("Judging…").foregroundStyle(.secondary) }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            case .done(let v):
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(v.verdict == .pass ? "✅ PASS" : "❌ FAIL").font(.headline)
                        .foregroundStyle(v.verdict == .pass ? .green : .red)
                        .accessibilityIdentifier("judge-verdict-badge")
                    Text("\(v.score)/5").font(.title2.bold()).accessibilityIdentifier("judge-score")
                    Text(meta(v)).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(v.criteria.enumerated()), id: \.offset) { _, c in
                    (Text(c.met ? "✅ " : "❌ ") + Text(c.criterion).bold() + Text(c.comment.isEmpty ? "" : ": \(c.comment)").foregroundStyle(.secondary))
                        .font(.callout)
                }
                Text(v.reason).font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            if case .done(let v) = card.state {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(v.verdict == .pass ? .green : .red).frame(width: 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("judge-verdict")
    }

    private func meta(_ v: JudgeVerdict) -> String {
        [v.model?.rawValue,
         v.seconds.map { String(format: "%.1fs", $0) },
         v.costUsd.map { String(format: "$%.4f", $0) },
         v.provider == .apiKey ? "API" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct HistoryCard: View {
    @Environment(JudgeViewModel.self) private var judge

    var body: some View {
        if !judge.history.isEmpty {
            card {
                Text("History (this session)").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow { ForEach(["Time", "Rubric", "Verdict", "Score", "Model", "Cost"], id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary) } }
                    ForEach(judge.history) { entry in
                        GridRow {
                            Text(entry.time, style: .time)
                            Text(entry.label)
                            Text(entry.verdict.verdict.rawValue.uppercased()).foregroundStyle(entry.verdict.verdict == .pass ? .green : .red)
                            Text("\(entry.verdict.score)/5")
                            Text(entry.verdict.model?.rawValue ?? "")
                            Text(entry.verdict.costUsd.map { String(format: "$%.4f", $0) } ?? "n/a")
                        }
                        .font(.callout)
                    }
                }
                .accessibilityIdentifier("judge-history")
                Text("\(judge.history.count) judgement(s) · total about \(String(format: "$%.4f", judge.totalCost))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Wraps its children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
