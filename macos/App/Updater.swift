import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle. The updater only starts once the release feed and EdDSA public key are configured in
/// Info.plist, so development builds don't show "unable to check for updates" errors.
@MainActor
final class Updater: ObservableObject {
    let controller: SPUStandardUpdaterController
    let isConfigured: Bool
    @Published var canCheckForUpdates = false

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        isConfigured = !key.isEmpty && !feed.isEmpty
        controller = SPUStandardUpdaterController(startingUpdater: isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.isConfigured || !updater.canCheckForUpdates)
    }
}
