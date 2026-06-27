import Foundation
import WallShared

/// Accepts new XPC connections and binds them to a `HelperService`.
/// Sets a code-signing requirement first so we reject anything that
/// isn't the real Wall app.
///
/// The daemon is launched on-demand by launchd (via its `MachServices`
/// key) and idle-exits once no connections remain. That matters for
/// updates: a resident root process holds `Contents/MacOS/WallHelper`
/// open, which blocks the user from replacing Wall.app via drag-install.
/// Exiting when idle means the binary is only held during an actual
/// session, and launchd relaunches us on the next XPC message. The app
/// opens a fresh connection per call and invalidates it after the reply
/// (see `XPCBlocker.withProxy`), so "idle" is the normal between-session
/// state, not an edge case.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    /// Quiet period after the last connection closes before we exit.
    /// Long enough to absorb a quick follow-up call, short enough that an
    /// update started moments after a session isn't blocked for long.
    private let idleTimeout: TimeInterval = 5

    private let lock = NSLock()
    private var activeConnections = 0
    private var idleExit: DispatchWorkItem?

    /// Arm the idle timer at startup so a helper that launches but never
    /// receives a usable message still exits instead of lingering.
    func beginIdleWatch() {
        lock.lock(); defer { lock.unlock() }
        scheduleIdleExitLocked()
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Non-throwing in macOS 15 SDK; failures surface later as
        // connection invalidation when the requirement actually evaluates.
        let requirement = #"identifier "\#(WallMainAppBundleID)" and anchor apple generic and certificate leaf[subject.OU] = "\#(WallTeamID)""#
        newConnection.setCodeSigningRequirement(requirement)

        newConnection.exportedInterface = NSXPCInterface(with: WallHelperProtocol.self)
        newConnection.exportedObject = HelperService()

        connectionOpened()
        newConnection.invalidationHandler = { [weak self] in self?.connectionClosed() }
        newConnection.interruptionHandler = { [weak self] in self?.connectionClosed() }

        newConnection.resume()
        return true
    }

    private func connectionOpened() {
        lock.lock(); defer { lock.unlock() }
        activeConnections += 1
        idleExit?.cancel()
        idleExit = nil
    }

    private func connectionClosed() {
        lock.lock(); defer { lock.unlock() }
        activeConnections = max(0, activeConnections - 1)
        if activeConnections == 0 { scheduleIdleExitLocked() }
    }

    /// Caller must hold `lock`.
    private func scheduleIdleExitLocked() {
        idleExit?.cancel()
        let work = DispatchWorkItem {
            NSLog("[WallHelper] idle — exiting so app updates aren't blocked")
            exit(0)
        }
        idleExit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }
}

/// The actual XPC service. Runs as root (the daemon's launch context),
/// so it can call pfctl / launchctl directly with no further elevation.
final class HelperService: NSObject, WallHelperProtocol {
    func block(maxSeconds: Int, withReply reply: @escaping (String?) -> Void) {
        do {
            try PFOperations.block(maxSeconds: maxSeconds)
            reply(nil)
        } catch {
            NSLog("[WallHelper] block failed: \(error)")
            reply(error.localizedDescription)
        }
    }

    func unblock(withReply reply: @escaping (String?) -> Void) {
        do {
            try PFOperations.unblock()
            reply(nil)
        } catch {
            NSLog("[WallHelper] unblock failed: \(error)")
            reply(error.localizedDescription)
        }
    }

    func ping(withReply reply: @escaping (String) -> Void) {
        reply("ok")
    }
}
