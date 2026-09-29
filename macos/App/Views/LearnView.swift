import SwiftUI
import TesterCore

struct LearnView: View {
    @Environment(LearnViewModel.self) private var learn

    var body: some View {
        @Bindable var learn = learn
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(learn.library.course.title).font(.headline)
                    Text(learn.progressSummary).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("learn-progress")
                }
                .padding(12)
                List(selection: $learn.selection) {
                    ForEach(learn.library.course.modules) { module in
                        Section(module.title) {
                            ForEach(module.lessons.compactMap { learn.library.lessons[$0] }) { lesson in
                                LessonRow(lesson: lesson).tag(LearnViewModel.Item.lesson(lesson.id))
                            }
                        }
                    }
                    Section("Reference") {
                        Label("Glossary", systemImage: "character.book.closed").tag(LearnViewModel.Item.glossary)
                            .accessibilityIdentifier("learn-glossary")
                        ForEach(learn.library.cheatSheets) { sheet in
                            Label(sheet.title, systemImage: "checklist").tag(LearnViewModel.Item.cheatSheet(sheet.id))
                                .accessibilityIdentifier("learn-cheatsheet-\(sheet.id)")
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("learn-outline")
            }
            .frame(width: 250)
            Divider()
            Group {
                switch learn.selection {
                case .lesson(let id):
                    if let lesson = learn.library.lessons[id] { LessonReader(lesson: lesson).id(id) }
                case .glossary:
                    GlossaryView()
                case .cheatSheet(let id):
                    if let sheet = learn.library.cheatSheets.first(where: { $0.id == id }) { CheatSheetView(sheet: sheet) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LessonRow: View {
    @Environment(LearnViewModel.self) private var learn
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: learn.lessonsRead.contains(lesson.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(learn.lessonsRead.contains(lesson.id) ? .green : .secondary)
            Text(lesson.title).lineLimit(2)
            Spacer(minLength: 0)
            if let best = learn.bestScores[lesson.id], !lesson.quiz.isEmpty {
                Text("\(best)/\(lesson.quiz.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if lesson.status == .draft {
                Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learn-lesson-\(lesson.id)")
    }
}

// MARK: - Lesson

private struct LessonReader: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat
    @Environment(JudgeViewModel.self) private var judge
    @Environment(LearnViewModel.self) private var learn
    let lesson: Lesson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title).font(.largeTitle.bold())
                    Text("\(lesson.minutes) min · \(lesson.summary)").foregroundStyle(.secondary)
                }
                if lesson.status == .draft {
                    Label("Draft content: to be replaced or reviewed by your QA lead.", systemImage: "pencil.and.outline")
                        .font(.callout).foregroundStyle(.orange)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("learn-draft-banner")
                }

                MarkdownView(markdown: learn.library.body(ofLesson: lesson.id), library: learn.library)
                    .accessibilityIdentifier("learn-body")

                if !lesson.keyTerms.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key terms").font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(lesson.keyTerms, id: \.self) { id in
                                if let entry = learn.library.glossaryEntry(id) { TermChip(entry: entry) }
                            }
                        }
                    }
                }

                if !lesson.practice.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Practice this").font(.headline)
                        ForEach(lesson.practice, id: \.self) { link in
                            Button {
                                learn.practice(link, app: app, chat: chat, judge: judge)
                            } label: {
                                Label(link.label, systemImage: learn.isDone(link, app: app, judge: judge) ? "checkmark.circle.fill" : "play.circle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("learn-practice")
                        }
                    }
                }

                if !lesson.quiz.isEmpty { QuizView(lesson: lesson) }

                Divider()
                HStack {
                    let read = learn.lessonsRead.contains(lesson.id)
                    Button(read ? "✓ Read (undo)" : "Mark as read") { learn.markRead(lesson.id, !read) }
                        .accessibilityIdentifier("learn-mark-read")
                    Spacer()
                    if let next = learn.library.lesson(after: lesson.id) {
                        Button("Next: \(next.title) →") {
                            learn.markRead(lesson.id)
                            learn.selection = .lesson(next.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("learn-next")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TermChip: View {
    let entry: GlossaryEntry
    @State private var showing = false

    var body: some View {
        Button(entry.term) { showing.toggle() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.term).font(.headline)
                    Text(entry.definition)
                }
                .padding(14)
                .frame(width: 300)
            }
            .accessibilityIdentifier("learn-term")
    }
}

// MARK: - Quiz

private struct QuizView: View {
    @Environment(LearnViewModel.self) private var learn
    let lesson: Lesson
    @State private var answers: [Int: Int] = [:]
    @State private var checked = false

    private var correct: Int { lesson.quiz.indices.filter { answers[$0] == lesson.quiz[$0].answer }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Check your understanding").font(.headline)
                Spacer()
                if let best = learn.bestScores[lesson.id] {
                    Text("Best: \(best)/\(lesson.quiz.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(lesson.quiz.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(item.question)").bold()
                    ForEach(Array(item.options.enumerated()), id: \.offset) { optionIndex, option in
                        Button {
                            guard !checked else { return }
                            answers[index] = optionIndex
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: symbol(question: index, option: optionIndex))
                                    .foregroundStyle(colour(question: index, option: optionIndex))
                                Text(option).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quiz-option")
                        .accessibilityAddTraits(answers[index] == optionIndex ? .isSelected : [])
                    }
                    if checked {
                        let right = answers[index] == item.answer
                        (Text(right ? "✅ Correct. " : "❌ Not quite. ").bold() + Text(item.explanation))
                            .font(.callout)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((right ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityIdentifier("quiz-explanation")
                    }
                }
            }
            HStack {
                if checked {
                    Text("\(correct) of \(lesson.quiz.count) correct").bold().accessibilityIdentifier("quiz-score")
                    Button("Retry") { answers = [:]; checked = false }.accessibilityIdentifier("quiz-retry")
                } else {
                    Button("Check answers") {
                        checked = true
                        learn.recordQuiz(lesson, correct: correct)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(answers.count < lesson.quiz.count)
                    .accessibilityIdentifier("quiz-check")
                    if answers.count < lesson.quiz.count {
                        Text("Answer every question to check.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quiz")
    }

    private func symbol(question: Int, option: Int) -> String {
        if checked && option == lesson.quiz[question].answer { return "checkmark.circle.fill" }
        if checked && answers[question] == option { return "xmark.circle.fill" }
        return answers[question] == option ? "largecircle.fill.circle" : "circle"
    }

    private func colour(question: Int, option: Int) -> Color {
        if checked && option == lesson.quiz[question].answer { return .green }
        if checked && answers[question] == option { return .red }
        return answers[question] == option ? .accentColor : .secondary
    }
}

// MARK: - Glossary and cheat sheets

private struct GlossaryView: View {
    @Environment(LearnViewModel.self) private var learn
    @State private var search = ""

    private var entries: [GlossaryEntry] {
        let all = learn.library.glossary.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.term.localizedCaseInsensitiveContains(query) || $0.definition.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Glossary").font(.title.bold())
                Spacer()
                TextField("Search terms", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .accessibilityIdentifier("glossary-search")
            }
            .padding(20)
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.term).font(.headline)
                    Text(entry.definition)
                    if !entry.seeAlso.isEmpty {
                        HStack(spacing: 6) {
                            Text("See also:").font(.caption).foregroundStyle(.secondary)
                            ForEach(entry.seeAlso, id: \.self) { id in
                                if let other = learn.library.glossaryEntry(id) {
                                    Button(other.term) { search = other.term }.buttonStyle(.link).font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("glossary-entry")
            }
        }
    }
}

private struct CheatSheetView: View {
    @Environment(LearnViewModel.self) private var learn
    let sheet: CheatSheet
    @State private var exporting = false

    var body: some View {
        let text = learn.library.body(ofCheatSheet: sheet.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(sheet.title).font(.largeTitle.bold())
                        Text(sheet.summary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Export…") { exporting = true }.accessibilityIdentifier("cheatsheet-export")
                }
                MarkdownView(markdown: text, library: learn.library)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileExporter(isPresented: $exporting, document: MarkdownDocument(text: "# \(sheet.title)\n\n\(text)"),
                      contentType: .markdownText, defaultFilename: "\(sheet.id).md") { _ in }
    }
}

// MARK: - Markdown rendering

/// Renders lesson Markdown: blocks from `MarkdownParser`, inline styling from `AttributedString(markdown:)`.
struct MarkdownView: View {
    let markdown: String
    let library: LearnLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text)).font(level == 1 ? .title.bold() : level == 2 ? .title2.bold() : .title3.bold())
                .padding(.top, 6)
        case .paragraph(let text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(inline(item)) }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(index + 1).").monospacedDigit(); Text(inline(item)) }
                }
            }
        case .quote(let text):
            let tone = calloutColour(text)
            Text(inline(text))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tone.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: 3) }
        case .code(_, let text):
            Text(verbatim: text).font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .image(let alt, let path):
            if let image = NSImage(contentsOf: library.imageURL(path)) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 640).accessibilityLabel(alt)
            } else {
                Text("[Missing image: \(alt)]").foregroundStyle(.red)
            }
        case .divider:
            Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func calloutColour(_ text: String) -> Color {
        if text.hasPrefix("**Warning") { return .red }
        if text.hasPrefix("**Draft") { return .orange }
        if text.hasPrefix("**Tip") { return .green }
        return .accentColor
    }
}
