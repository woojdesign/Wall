import Foundation

/// All packet-filter / launchd operations the helper performs. Runs as root
/// inside the helper's daemon context, so no osascript / sudo / elevation
/// is needed — just direct Process calls to system tools.
///
/// Rules and structure mirror the legacy shell-script path in the main
/// app's earlier PFBlocker, now centralized here as the helper owns them.
enum PFOperations {
    /// Drop outbound to the public internet; pass loopback, LAN, link-local,
    /// multicast, DHCP. `set block-policy` is intentionally absent — `set`
    /// directives are only valid at the top level of pf.conf, not inside an
    /// anchor; macOS 15.6.1's pf rejects it as a syntax error. `block drop`
    /// already specifies the drop action, so the `set` was redundant anyway.
    static let anchorRules = """
    block drop out all
    pass out quick on lo0 all
    pass out quick inet proto udp from any to any port { 67, 68 }
    pass out quick inet from any to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 }
    pass out quick inet6 from any to { fe80::/10, fc00::/7, ff00::/8 }
    """

    static func block(maxSeconds: Int) throws {
        let anchorFile = "/etc/pf.anchors/wall.block"
        // pfctl on macOS 15.6.1 rejects a final rule line with no trailing
        // newline as a syntax error, so the `\n` is load-bearing.
        try (anchorRules + "\n").write(toFile: anchorFile, atomically: true, encoding: .utf8)

        let mainConfig = """
        scrub-anchor "com.apple/*"
        nat-anchor "com.apple/*"
        rdr-anchor "com.apple/*"
        dummynet-anchor "com.apple/*"
        anchor "com.apple/*"
        load anchor "com.apple" from "/etc/pf.anchors/com.apple"
        anchor "wall.block"
        load anchor "wall.block" from "\(anchorFile)"
        """
        let mainPath = "/tmp/wall.main.conf"
        try (mainConfig + "\n").write(toFile: mainPath, atomically: true, encoding: .utf8)

        try run("/sbin/pfctl", ["-f", mainPath])
        // -E can report "pf already enabled" non-zero; that's benign.
        _ = try? run("/sbin/pfctl", ["-E"])

        try installDeadman(seconds: maxSeconds)
    }

    static func unblock() throws {
        // All best-effort: missing anchors / unloaded job are non-fatal.
        _ = try? run("/bin/launchctl", ["bootout", "system/design.wooj.wall.deadman"])
        _ = try? run("/sbin/pfctl", ["-a", "wall.block", "-F", "all"])
        _ = try? run("/sbin/pfctl", ["-f", "/etc/pf.conf"])
    }

    /// Install a launchd-owned dead-man's-switch: if Wall (or this helper)
    /// dies, pf still flushes after `seconds`. Survives osascript-style
    /// process-group teardowns because launchd owns it.
    private static func installDeadman(seconds: Int) throws {
        let label = "design.wooj.wall.deadman"
        let plistPath = "/tmp/wall-deadman.plist"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(label)</string>
          <key>RunAtLoad</key><true/>
          <key>ProgramArguments</key>
          <array>
            <string>/bin/sh</string>
            <string>-c</string>
            <string>sleep \(seconds); pfctl -a wall.block -F all; pfctl -f /etc/pf.conf</string>
          </array>
        </dict>
        </plist>
        """
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        _ = try? run("/bin/launchctl", ["bootout", "system/\(label)"])
        try run("/bin/launchctl", ["bootstrap", "system", plistPath])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "PFOperations", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                                        "\(path) \(args.joined(separator: " "))\n\(out)"])
        }
        return out
    }
}
