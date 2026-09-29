import Foundation

/// A tester's verdict on one chatbot reply.
public struct Flag: Codable, Sendable, Equatable {
    public enum Verdict: String, Codable, Sendable, CaseIterable { case fail, pass }
    public enum Severity: String, Codable, Sendable, CaseIterable, Identifiable {
        case low = "Low", medium = "Medium", high = "High", critical = "Critical"
        public var id: String { rawValue }
    }

    public var verdict: Verdict
    public var category: String
    public var severity: Severity
    public var expected: String
    public var note: String

    public init(verdict: Verdict = .fail, category: String = Content.categories.first ?? "Other",
                severity: Severity = .medium, expected: String = "", note: String = "") {
        self.verdict = verdict
        self.category = category
        self.severity = severity
        self.expected = expected
        self.note = note
    }

    /// e.g. "❌ High · Hallucination" or "✅ Pass · Persona & tone"
    public var summary: String {
        verdict == .fail ? "❌ \(severity.rawValue) · \(category)" : "✅ Pass · \(category)"
    }
}

/// What a message was sent with. Stored with each message so reports and re-runs are accurate.
public struct MessageContext: Codable, Sendable, Equatable {
    public var model: String
    public var systemPrompt: String
    public var options: ChatOptions
    /// e.g. "Free chat", "Target bot: ShopBot · Level 3", "Mission: Test for bias"
    public var modeLabel: String
    public var botId: String?

    public init(model: String, systemPrompt: String, options: ChatOptions, modeLabel: String, botId: String? = nil) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.options = options
        self.modeLabel = modeLabel
        self.botId = botId
    }
}

/// One message in a saved session or report.
public struct SessionMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant, error }

    public var id: UUID
    public var role: Role
    public var text: String
    public var context: MessageContext?
    public var meta: String?
    public var flag: Flag?
    /// A user message whose request failed (left out of the conversation sent to the model).
    public var failed: Bool

    public init(id: UUID = UUID(), role: Role, text: String, context: MessageContext? = nil, meta: String? = nil, flag: Flag? = nil, failed: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
        self.meta = meta
        self.flag = flag
        self.failed = failed
    }
}

/// A saved chat, for the History list.
public struct ChatSession: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var started: Date
    public var updated: Date
    public var modeLabel: String
    public var messages: [SessionMessage]

    public init(id: UUID = UUID(), started: Date = Date(), modeLabel: String, messages: [SessionMessage] = []) {
        self.id = id
        self.started = started
        self.updated = started
        self.modeLabel = modeLabel
        self.messages = messages
    }

    public var title: String {
        messages.first { $0.role == .user }.map { String($0.text.prefix(60)) } ?? "Empty chat"
    }
    public var flagCount: Int { messages.filter { $0.flag != nil }.count }
}

/// Builds the Markdown bug report from a chat. Ported from the web app's `buildReport` (public/js/flags.js).
public enum ReportBuilder {
    private static func quote(_ text: String) -> String {
        (text.isEmpty ? "(empty)" : text).split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
    }

    private static func oneLine(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " ") }

    public static func markdown(for messages: [SessionMessage], date: Date = Date()) -> String {
        let chat = messages.filter { $0.role != .error }
        let ctx = chat.first?.context
        let flagged = chat.filter { $0.flag != nil }
        let fails = flagged.filter { $0.flag?.verdict == .fail }
        let passes = flagged.filter { $0.flag?.verdict == .pass }
        var out: [String] = []

        out += ["# Chatbot test session report", ""]
        out.append("- **Date:** \(date.formatted(date: .abbreviated, time: .shortened))")
        out.append("- **Model:** `\(ctx?.model ?? "n/a")`")
        out.append("- **Mode:** \(ctx?.modeLabel ?? "n/a")")
        out.append("- **Settings:** \(ctx?.options.summary ?? "n/a")")
        let systemPromptLine: String
        if ctx?.botId != nil { systemPromptLine = "(hidden: target bot)" }
        else if let sp = ctx?.systemPrompt, !sp.isEmpty { systemPromptLine = "see below" }
        else { systemPromptLine = "(none)" }
        out.append("- **System prompt:** \(systemPromptLine)")
        out.append("- **Result:** \(fails.count) issue(s) found, \(passes.count) check(s) passed, \(chat.filter { $0.role == .user }.count) message(s) sent")
        out.append("")
        if ctx?.botId == nil, let sp = ctx?.systemPrompt, !sp.isEmpty {
            out += ["## System prompt", "", "```", sp, "```", ""]
        }

        out += ["## Issues", ""]
        if fails.isEmpty { out += ["_No issues flagged._", ""] }
        for (number, message) in fails.enumerated() {
            guard let flag = message.flag else { continue }
            let index = chat.firstIndex { $0.id == message.id } ?? 0
            let userTurns = chat[..<index].filter { $0.role == .user }
            let mctx = message.context
            let firstNote = flag.note.split(separator: "\n").first.map(String.init) ?? ""
            out += ["### \(number + 1). [\(flag.severity.rawValue)] \(flag.category)\(firstNote.isEmpty ? "" : ": \(firstNote)")", ""]
            out += ["**Steps to reproduce**", ""]
            out.append("1. Model `\(mctx?.model ?? "?")`, \(mctx?.options.summary ?? "?"), mode: \(mctx?.modeLabel ?? "?")")
            var step = 2
            if mctx?.botId == nil, let sp = mctx?.systemPrompt, !sp.isEmpty {
                out.append("2. Set the system prompt shown above")
                step = 3
            }
            for turn in userTurns {
                out.append("\(step). Send: \"\(oneLine(turn.text))\"")
                step += 1
            }
            out.append("")
            out += ["**Expected:** \(flag.expected.isEmpty ? "_not specified_" : flag.expected)", ""]
            out += ["**Actual:**", "", quote(message.text), ""]
            if !flag.note.isEmpty { out += ["**Notes:** \(flag.note)", ""] }
            out += ["_Reply meta: \(message.meta ?? "")_", ""]
        }

        if !passes.isEmpty {
            out += ["## Passed checks", ""]
            for message in passes {
                guard let flag = message.flag else { continue }
                out.append("- **\(flag.category)**: \(flag.note.isEmpty ? oneLine(String(message.text.prefix(80))) : flag.note)")
            }
            out.append("")
        }

        out += ["## Full transcript", ""]
        for message in chat {
            let tag = message.flag.map { $0.verdict == .fail ? " ❌" : " ✅" } ?? ""
            out.append(message.role == .user ? "**User:**" : "**Assistant**\(tag) _(\(message.meta ?? ""))_:")
            out += ["", quote(message.text), ""]
        }
        return out.joined(separator: "\n")
    }
}
