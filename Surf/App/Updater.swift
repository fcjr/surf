import Sparkle

/// Sparkle auto-updates. The appcast lives on the latest GitHub release (see SUFeedURL).
@MainActor
enum Updater {
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
