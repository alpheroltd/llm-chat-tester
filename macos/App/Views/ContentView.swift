import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app
    @State private var showOnboarding = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            VStack(spacing: 0) {
                // Tabs live in the content area rather than the toolbar, which overflows at narrow widths.
                Picker("View", selection: $app.tab) {
                    ForEach(AppTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.vertical, 8)
                .accessibilityIdentifier("tabs")
                Divider()
                Group {
                    switch app.tab {
                    case .learn: LearnView()
                    case .chat: ChatView()
                    case .testCases: TestCasesView()
                    case .judge: JudgeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar { toolbarContent }
        }
        // The chat sidebar (model, mode, settings) isn't needed while reading, so Learn gets the full width.
        // Testers can still open it with the sidebar button.
        .onChange(of: app.tab, initial: true) { columns = app.tab == .learn ? .detailOnly : .all }
        .task {
            await app.refreshModels()
            await app.refreshClaude()
            if !app.hasCompletedOnboarding || !app.ollamaStatus.isOK { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showOnboarding = true
            } label: {
                Label("Setup", systemImage: "checklist")
            }
            .help("Setup checklist")
        }
    }
}

struct StatusBadge: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(status.label)
    }

    private var color: Color {
        switch status {
        case .checking: .gray
        case .ok: .green
        case .problem: .red
        }
    }
}

struct ComingSoonView: View {
    let feature: String
    let milestone: Int

    var body: some View {
        ContentUnavailableView(
            "\(feature) is coming",
            systemImage: "hammer",
            description: Text("This arrives in milestone \(milestone). It will reach you automatically via Check for Updates.")
        )
    }
}
