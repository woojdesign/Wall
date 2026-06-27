import Foundation
import ServiceManagement

/// Manages the WallHelper privileged daemon via SMAppService.
///
/// Registration is idempotent — safe to call on every launch. The first
/// successful call adds an item to System Settings → Login Items & Extensions
/// → Background; the user has to flip it on once. From then on launchd
/// auto-starts the helper, and Wall talks to it over XPC with no prompts.
///
/// Until the user approves, `status != .enabled` and `PFBlocker` falls back
/// to the legacy osascript path so the app stays functional.
@MainActor
final class HelperManager: ObservableObject {
    static let shared = HelperManager()

    static let plistName = "design.wooj.wall.helper.plist"

    @Published private(set) var status: SMAppService.Status

    private let service: SMAppService

    private init() {
        let s = SMAppService.daemon(plistName: Self.plistName)
        self.service = s
        self.status = s.status
    }

    /// Try to install the helper. Idempotent — call on every launch.
    ///
    /// We always call `register()` (rather than gating on `.notRegistered`)
    /// because `.notFound` means "previously registered but now stale,"
    /// which is exactly the state left behind by an unnotarized → notarized
    /// transition or a bundle move. Re-registering refreshes the record.
    /// `register()` is documented as idempotent: it registers if not yet
    /// registered, updates the registration if already.
    func registerIfNeeded() {
        do {
            try service.register()
        } catch {
            NSLog("[Wall] SMAppService.register failed: \(error)")
        }
        status = service.status
    }

    /// Re-poll the framework — call when returning to foreground in case
    /// the user toggled approval in System Settings while Wall was inactive.
    func refresh() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
