import Foundation
import WallShared

protocol InternetBlocker: Sendable {
    func block(maxSeconds: Int) async throws
    func unblock() async throws
}

/// Safe default during development: logs intent, touches nothing on the network.
struct MockBlocker: InternetBlocker {
    func block(maxSeconds: Int) async throws {
        NSLog("[Wall] MockBlocker.block(maxSeconds: %d) — no-op", maxSeconds)
    }
    func unblock() async throws {
        NSLog("[Wall] MockBlocker.unblock() — no-op")
    }
}

/// Real blocker. Routes to the XPC helper when SMAppService reports
/// `.enabled`; falls back to the legacy osascript admin path otherwise.
/// The fallback exists so the app keeps working during the gap between
/// SMAppService.register() and the user toggling the background item on.
struct PFBlocker: InternetBlocker {
    func block(maxSeconds: Int) async throws {
        if await HelperManager.shared.isEnabled {
            try await XPCBlocker().block(maxSeconds: maxSeconds)
        } else {
            try await OSAScriptBlocker().block(maxSeconds: maxSeconds)
        }
    }

    func unblock() async throws {
        if await HelperManager.shared.isEnabled {
            try await XPCBlocker().unblock()
        } else {
            try await OSAScriptBlocker().unblock()
        }
    }
}

// MARK: - XPC path (no prompts, helper does pfctl as root)

struct XPCBlocker: InternetBlocker {
    func block(maxSeconds: Int) async throws {
        try await withProxy { proxy, done in
            proxy.block(maxSeconds: maxSeconds) { errorMessage in
                done(errorMessage)
            }
        }
    }

    func unblock() async throws {
        try await withProxy { proxy, done in
            proxy.unblock { errorMessage in
                done(errorMessage)
            }
        }
    }

    /// Opens an XPC connection, hands the typed proxy to `body`, and
    /// resumes the continuation on whatever `body` reports.
    private func withProxy(
        _ body: @escaping (WallHelperProtocol, @escaping (String?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let connection = NSXPCConnection(
                machServiceName: WallHelperMachServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: WallHelperProtocol.self)

            // Resume-once guard: NSXPCConnection can deliver invalidationHandler
            // *and* an errorHandler reply for the same failure; we must only
            // resume the continuation a single time.
            let resumed = ManagedAtomic(false)
            func resumeOnce(_ result: Result<Void, Error>) {
                if resumed.exchange(true) { return }
                connection.invalidate()
                cont.resume(with: result)
            }

            connection.invalidationHandler = {
                resumeOnce(.failure(NSError(
                    domain: "WallHelperXPC", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "connection invalidated before reply"]
                )))
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                resumeOnce(.failure(error))
            } as? WallHelperProtocol

            guard let proxy else {
                resumeOnce(.failure(NSError(
                    domain: "WallHelperXPC", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "could not obtain XPC proxy"]
                )))
                return
            }

            body(proxy) { errorMessage in
                if let msg = errorMessage {
                    resumeOnce(.failure(NSError(
                        domain: "WallHelper", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    )))
                } else {
                    resumeOnce(.success(()))
                }
            }
        }
    }
}

/// Minimal atomic flag — avoids importing the swift-atomics package for
/// a single boolean we use once per call.
private final class ManagedAtomic: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(_ initial: Bool) { value = initial }
    /// Returns the previous value.
    func exchange(_ new: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let old = value
        value = new
        return old
    }
}

// MARK: - osascript fallback (used before helper is approved)

/// The legacy path: builds the same shell script, runs it once via an
/// `osascript ... with administrator privileges` Touch-ID / password prompt.
/// Kept around verbatim so first-run users (or anyone who hasn't yet
/// approved the helper) still get a working block.
struct OSAScriptBlocker: InternetBlocker {
    func block(maxSeconds: Int) async throws {
        let script = """
        set -e
        ANCHOR_FILE=/etc/pf.anchors/wall.block
        MAIN=$(mktemp /tmp/wall.main.XXXXXX)
        LABEL=design.wooj.wall.deadman
        PLIST=/tmp/wall-deadman.plist
        cat > "$ANCHOR_FILE" <<'PF'
        \(Self.anchorRules)
        PF
        cat > "$MAIN" <<PFMAIN
        scrub-anchor "com.apple/*"
        nat-anchor "com.apple/*"
        rdr-anchor "com.apple/*"
        dummynet-anchor "com.apple/*"
        anchor "com.apple/*"
        load anchor "com.apple" from "/etc/pf.anchors/com.apple"
        anchor "wall.block"
        load anchor "wall.block" from "$ANCHOR_FILE"
        PFMAIN
        pfctl -f "$MAIN"
        pfctl -E
        launchctl bootout system/$LABEL 2>/dev/null || true
        cat > "$PLIST" <<PLISTEOF
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>$LABEL</string>
          <key>RunAtLoad</key><true/>
          <key>ProgramArguments</key>
          <array>
            <string>/bin/sh</string>
            <string>-c</string>
            <string>sleep \(maxSeconds); pfctl -a wall.block -F all; pfctl -f /etc/pf.conf</string>
          </array>
        </dict>
        </plist>
        PLISTEOF
        launchctl bootstrap system "$PLIST"
        """
        try await Self.runAsAdmin(script)
    }

    func unblock() async throws {
        let script = """
        launchctl bootout system/design.wooj.wall.deadman 2>/dev/null || true
        pfctl -a wall.block -F all 2>/dev/null || true
        pfctl -f /etc/pf.conf 2>/dev/null || true
        """
        try await Self.runAsAdmin(script)
    }

    /// `set block-policy` removed — invalid inside an anchor on macOS 15.6.1.
    /// `block drop` already specifies the drop action. See PFOperations.swift
    /// for the same rules in the helper-owned path.
    static let anchorRules = """
    block drop out all
    pass out quick on lo0 all
    pass out quick inet proto udp from any to any port { 67, 68 }
    pass out quick inet from any to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 }
    pass out quick inet6 from any to { fe80::/10, fc00::/7, ff00::/8 }
    """

    static func runAsAdmin(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("wall-\(UUID().uuidString).sh")
                    try script.write(to: tmp, atomically: true, encoding: .utf8)
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    let osa = "do shell script \"/bin/sh \(tmp.path)\" with administrator privileges"
                    try runProcess("/usr/bin/osascript", ["-e", osa])
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    static func runProcess(_ launchPath: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "Wall.OSAScriptBlocker", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: out])
        }
        return out
    }
}

enum BlockerFactory {
    /// Real pf-based blocker by default — Wall is meant to actually block.
    /// `WALL_MOCK_BLOCK=1` switches to the no-op mock for dev sessions where
    /// you don't want to cut your own network connection (e.g., iterating on
    /// UI from a shell that's also being used to inspect the app). The
    /// legacy `WALL_REAL_BLOCK=1` still forces real for symmetry.
    static func make() -> InternetBlocker {
        let env = ProcessInfo.processInfo.environment
        if env["WALL_REAL_BLOCK"] == "1" { return PFBlocker() }
        if env["WALL_MOCK_BLOCK"] == "1" { return MockBlocker() }
        return PFBlocker()
    }
}
