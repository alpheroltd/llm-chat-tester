import Sparkle
import SwiftUI

@main
struct LLMChatTesterApp: App {
    @State private var app = AppState()
    @State private var chat = ChatViewModel()
    @State private var testCases = TestCasesViewModel()
    @State private var judge = JudgeViewModel()
    @State private var learn = LearnViewModel()
    private let updater = Updater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .environment(chat)
                .environment(testCases)
                .environment(judge)
                .environment(learn)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    chat.clear() // the previous chat stays in History
                    app.winBannerBotID = nil
                }
                    .keyboardShortcut("k", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(updater: updater)
                .environment(app)
        }
    }
}
