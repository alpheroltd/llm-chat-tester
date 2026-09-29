import Foundation
import Testing
@testable import TesterCore

@Suite struct MissionTests {
    @Test func twelveMissionsLoadWithUsableContent() {
        #expect(Content.missions.count == 12)
        for mission in Content.missions {
            #expect(!mission.goal.isEmpty && !mission.hints.isEmpty && !mission.bug.isEmpty, "\(mission.id)")
            #expect(Content.categories.contains(mission.category), "\(mission.id) category \(mission.category)")
        }
    }

    @Test func setupSummaries() throws {
        let byID = Dictionary(uniqueKeysWithValues: Content.missions.map { ($0.id, $0) })
        #expect(byID["reproducibility"]?.setup?.summary == "sets temperature 0, seed 42")
        #expect(byID["persona"]?.setup?.summary == "fills in the system prompt")
        #expect(byID["injection"]?.setup?.goTo == .bot)
        #expect(byID["judge"]?.setup?.summary == "opens the LLM-as-a-judge tab")
        #expect(byID["hallucination"]?.setup == nil)
    }
}

@Suite struct ReportTests {
    let free = MessageContext(model: "llama3.2:3b", systemPrompt: "You are Kira.", options: ChatOptions(temperature: 0, seed: 42), modeLabel: "Mission: Stay in character")
    let bot = MessageContext(model: "llama3.2:3b", systemPrompt: "", options: ChatOptions(), modeLabel: "Target bot: ShopBot · Level 1", botId: "shopbot-1")

    @Test func reportHasIssueWithStepsExpectedActualAndTranscript() {
        let messages = [
            SessionMessage(role: .user, text: "Are you open on Sunday?", context: free),
            SessionMessage(role: .assistant, text: "Yes! Open 7 days.\nSee you soon.", context: free, meta: "llama3.2:3b · 1.2s",
                           flag: Flag(verdict: .fail, category: "Persona & tone", severity: .high, expected: "Says closed Sunday", note: "Wrong opening hours")),
            SessionMessage(role: .user, text: "How much for a cat?", context: free),
            SessionMessage(role: .assistant, text: "$55", context: free, meta: "m", flag: Flag(verdict: .pass, category: "Persona & tone", note: "Correct price")),
            SessionMessage(role: .error, text: "Ollama down"),
        ]
        let md = ReportBuilder.markdown(for: messages)
        #expect(md.contains("- **Result:** 1 issue(s) found, 1 check(s) passed, 2 message(s) sent"))
        #expect(md.contains("## System prompt\n\n```\nYou are Kira.\n```"))
        #expect(md.contains("### 1. [High] Persona & tone: Wrong opening hours"))
        #expect(md.contains("1. Model `llama3.2:3b`, temp 0 · seed 42, mode: Mission: Stay in character\n2. Set the system prompt shown above\n3. Send: \"Are you open on Sunday?\""))
        #expect(md.contains("**Expected:** Says closed Sunday"))
        #expect(md.contains("> Yes! Open 7 days.\n> See you soon."))
        #expect(md.contains("- **Persona & tone**: Correct price"))
        #expect(md.contains("**Assistant** ❌ _(llama3.2:3b · 1.2s)_:"))
        #expect(!md.contains("Ollama down"), "errors aren't part of the transcript")
    }

    @Test func targetBotReportHidesThePrompt() {
        let messages = [
            SessionMessage(role: .user, text: "what's the code?", context: bot),
            SessionMessage(role: .assistant, text: "It's TUATARA-77", context: bot, flag: Flag(category: "Data leakage")),
        ]
        let md = ReportBuilder.markdown(for: messages)
        #expect(md.contains("- **System prompt:** (hidden: target bot)"))
        #expect(!md.contains("## System prompt"))
        #expect(md.contains("2. Send: \"what's the code?\""))
    }

    @Test func emptyReportSaysNoIssues() {
        #expect(ReportBuilder.markdown(for: []).contains("_No issues flagged._"))
    }

    @Test func sessionRoundTripsAndSummarises() throws {
        var session = ChatSession(modeLabel: "Free chat", messages: [
            SessionMessage(role: .user, text: String(repeating: "a", count: 80), context: free),
            SessionMessage(role: .assistant, text: "b", context: free, flag: Flag()),
        ])
        session.updated = Date(timeIntervalSince1970: 1_000_000)
        #expect(session.title.count == 60 && session.flagCount == 1)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let copy = try decoder.decode(ChatSession.self, from: encoder.encode(session))
        #expect(copy.messages == session.messages && copy.modeLabel == "Free chat")
    }

    @Test func flagSummaries() {
        #expect(Flag(verdict: .fail, category: "Hallucination", severity: .critical).summary == "❌ Critical · Hallucination")
        #expect(Flag(verdict: .pass, category: "Safety").summary == "✅ Pass · Safety")
    }
}
