import SwiftUI
import Sparkle

/// Owns the Sparkle updater for the app's lifetime.
///
/// `SPUStandardUpdaterController` with `startingUpdater: true` boots the
/// updater at launch and (because `SUEnableAutomaticChecks` is omitted from
/// Info.plist) asks the user once whether to allow automatic checks. After
/// that it polls the appcast at `SUFeedURL` on its own schedule; the
/// "Check for Updates…" menu item drives a manual check.
///
/// The feed URL and the EdDSA public key that validates downloads both live
/// in the bundle's Info.plist (written by scripts/build-app.sh).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    /// Mirrors the updater's readiness so the menu item can disable itself
    /// while a check is already in flight.
    @Published var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// Menu-bar "Check for Updates…" item, styled like the other plain menu rows.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .buttonStyle(.plain)
            .disabled(!updater.canCheckForUpdates)
    }
}
