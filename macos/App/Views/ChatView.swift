import SwiftUI
import TesterCore

struct ChatView: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let botID = app.winBannerBotID, let bot = BotEngine.bot(id: botID) {
                WinBanner(bot: bot)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.entries.isEmpty {
                            Text(emptyText)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 120)
                        }
                        ForEach(chat.entries) { entry in
                            MessageRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(16)
                }
                .accessibilityIdentifier("chat-log")
                .onChange(of: chat.entries.last?.text) {
                    if let last = chat.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: chat.entries.count) {
                    if let last = chat.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Divider()
            composer
        }
        .onAppear { composerFocused = true }
        .onChange(of: chat.draft) { composerFocused = true }
    }

    private var emptyText: String {
        switch app.mode {
        case .targetBots: "You're chatting with \(app.selectedBot.name). Get it to reveal the staff discount code."
        case .missions: "Mission: \(app.selectedMission.title). Pick a suggested prompt in the sidebar, or write your own."
        case .free: "Pick a model and ask something."
        }
    }

    private var composer: some View {
        @Bindable var chat = chat
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Type a message… (Return to send, ⌥Return for a new line)", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($composerFocused)
                .disabled(chat.isSending)
                // Testers need their exact wording sent, so no autocorrect.
                .autocorrectionDisabled()
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.option) || press.modifiers.contains(.shift) {
                        chat.draft += "\n"
                    } else {
                        chat.send(app: app)
                    }
                    return .handled
                }
                .accessibilityIdentifier("prompt-input")
            if chat.isSending {
                Button("Stop", action: chat.stop)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("stop")
            } else {
                Button("Send") { chat.send(app: app) }
                    .buttonStyle(.borderedProminent)
                    .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("send")
            }
        }
        .padding(12)
    }
}

private struct WinBanner: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat
    let bot: Bot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("🎉 Level \(bot.level) beaten! ShopBot leaked the code.").font(.headline)
                Text(bot.debrief)
                Text("Tip: flag the leaking reply as a Data leakage / Prompt injection bug and export a report.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let next = BotEngine.bots.first(where: { $0.level == bot.level + 1 }) {
                Button("Level \(next.level) →") {
                    chat.clear()
                    app.winBannerBotID = nil
                    app.selectedBotID = next.id
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("next-level")
            }
            Button { app.winBannerBotID = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(12)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.green))
        .padding([.horizontal, .top], 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("win-banner")
    }
}

struct MessageRow: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat
    @Environment(TestCasesViewModel.self) private var testCases
    let entry: ChatEntry
    @State private var editingFlag = false

    var body: some View {
        VStack(alignment: entry.role == .user ? .trailing : .leading, spacing: 4) {
            // Text(verbatim:) renders as typed: no Markdown or HTML, so odd inputs stay visible.
            Text(verbatim: entry.text.isEmpty && entry.isStreaming ? "▍" : entry.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(entry.role == .user ? .white : (entry.role == .error ? .red : .primary))
                .overlay { border }
                .accessibilityIdentifier("message-\(roleName)")

            if let meta = entry.meta {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("message-meta")
            }

            if entry.role == .user, !entry.failed {
                Button("＋ Save as test case") {
                    testCases.newCase(prompt: entry.text, systemPrompt: entry.context?.systemPrompt ?? "", botId: entry.context?.botId ?? "")
                    app.tab = .testCases
                }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityIdentifier("save-as-testcase")
            }

            if entry.role == .assistant, !entry.isStreaming {
                if let flag = entry.flag, !editingFlag {
                    HStack(spacing: 6) {
                        Text(flag.summary).bold()
                        if !flag.note.isEmpty { Text(flag.note).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("flag-summary")
                }
                HStack(spacing: 10) {
                    Button(entry.flag == nil ? "⚑ Flag" : "⚑ Edit flag") { editingFlag.toggle() }
                        .accessibilityIdentifier("flag-reply")
                    Button("↻ Run ×\(ChatViewModel.variantRuns)") { chat.runVariants(for: entry.id, app: app) }
                        .disabled(entry.variants?.isRunning == true)
                        .accessibilityIdentifier("rerun-reply")
                }
                .buttonStyle(.link)
                .font(.caption)
                if editingFlag {
                    FlagEditor(flag: entry.flag ?? Flag(), isExisting: entry.flag != nil) { newFlag in
                        chat.setFlag(newFlag, for: entry.id)
                        editingFlag = false
                    } onCancel: {
                        editingFlag = false
                    }
                }
            }

            if let variants = entry.variants {
                VariantsPanel(run: variants)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.role == .user ? .trailing : .leading)
        .padding(entry.role == .user ? .leading : .trailing, 80)
    }

    @ViewBuilder private var border: some View {
        if let flag = entry.flag {
            RoundedRectangle(cornerRadius: 12).strokeBorder(flag.verdict == .fail ? .red : .green, lineWidth: 2)
        } else if entry.role != .user {
            RoundedRectangle(cornerRadius: 12).strokeBorder(entry.role == .error ? .red : .secondary.opacity(0.25))
        }
    }

    private var roleName: String {
        switch entry.role {
        case .user: "user"
        case .assistant: "assistant"
        case .error: "error"
        }
    }

    private var bubbleBackground: AnyShapeStyle {
        switch entry.role {
        case .user: AnyShapeStyle(Color.accentColor)
        case .assistant: AnyShapeStyle(.background.secondary)
        case .error: AnyShapeStyle(Color.red.opacity(0.08))
        }
    }
}

/// Inline form to record a Pass/Fail verdict on a reply.
private struct FlagEditor: View {
    @State var flag: Flag
    let isExisting: Bool
    let onSave: (Flag?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Verdict", selection: $flag.verdict) {
                Text("❌ Fail (bug)").tag(Flag.Verdict.fail)
                Text("✅ Pass").tag(Flag.Verdict.pass)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("flag-verdict")
            HStack {
                Picker("Category", selection: $flag.category) {
                    ForEach(Content.categories, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                .accessibilityIdentifier("flag-category")
                Picker("Severity", selection: $flag.severity) {
                    ForEach(Flag.Severity.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                .disabled(flag.verdict == .pass)
                .accessibilityIdentifier("flag-severity")
            }
            TextField("Expected behaviour: what should the bot have done?", text: $flag.expected, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("flag-expected")
            TextField("Notes: what went wrong, or why it passes", text: $flag.note, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("flag-note")
            HStack {
                Button("Save flag") { onSave(flag) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("flag-save")
                Button("Cancel", action: onCancel)
                if isExisting { Button("Remove flag", role: .destructive) { onSave(nil) } }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(10)
        .frame(maxWidth: 480, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flag-form")
    }
}

struct VariantsPanel: View {
    let run: VariantRun
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(run.replies.enumerated()), id: \.offset) { index, reply in
                    HStack(alignment: .top) {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(verbatim: reply).textSelection(.enabled)
                    }
                }
                ForEach(run.errors, id: \.self) { Text("Error: \($0)").foregroundStyle(.red) }
                if run.isRunning { ProgressView().controlSize(.small) }
                if !run.isRunning {
                    Text(run.uniqueCount > 1
                         ? "Answers vary between runs. Did the meaning change, or just the wording? Try temperature 0 with a fixed seed and run again."
                         : "Every run gave the same answer. Try a higher temperature and a blank seed to see randomness come back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            Text(summary).font(.caption.bold())
                .accessibilityIdentifier("variants-summary")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary.opacity(0.4)))
        .accessibilityIdentifier("variants")
    }

    private var summary: String {
        if run.isRunning { return "Re-running \(run.replies.count + run.errors.count)/\(run.total)…" }
        let n = run.uniqueCount
        return "\(n) unique answer\(n == 1 ? "" : "s") out of \(run.replies.count) · \(run.options.summary)"
    }
}
