import SwiftUI
import TesterCore

/// Earlier chats, newest first. Opening one restores it so you can keep going, flag replies or export a report.
struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Environment(ChatViewModel.self) private var chat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History").font(.title2.bold()).padding(16)
            if chat.sessions.isEmpty {
                ContentUnavailableView("No saved chats yet", systemImage: "clock",
                                       description: Text("Chats are saved automatically as you go."))
            } else {
                List(chat.sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: session.title).font(.headline).lineLimit(1)
                            Text("\(session.modeLabel) · \(session.messages.filter { $0.role == .user }.count) message(s)\(session.flagCount > 0 ? " · \(session.flagCount) flagged" : "") · \(session.updated.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") { open(session) }.accessibilityIdentifier("history-open")
                        Button("Delete", role: .destructive) { chat.deleteSession(session) }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("history-row")
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 460)
    }

    private func open(_ session: ChatSession) {
        // Put the app back in the mode the chat was held in, so new messages go to the same target.
        let context = session.messages.first { $0.context != nil }?.context
        if let botId = context?.botId, BotEngine.bot(id: botId) != nil {
            app.mode = .targetBots
            app.selectedBotID = botId
        } else if let label = context?.modeLabel, label.hasPrefix("Mission: "),
                  let mission = Content.missions.first(where: { "Mission: \($0.title)" == label }) {
            app.mode = .missions
            app.selectedMissionID = mission.id
        } else {
            app.mode = .free
        }
        if let prompt = context?.systemPrompt, context?.botId == nil { app.systemPrompt = prompt }
        app.winBannerBotID = nil
        app.tab = .chat
        chat.open(session)
        dismiss()
    }
}
