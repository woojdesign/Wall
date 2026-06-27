import Foundation

/// Mach service name the privileged helper publishes — used by both ends to
/// establish the XPC connection. Matches the helper's launchd plist Label and
/// MachServices entry.
public let WallHelperMachServiceName = "design.wooj.wall.helper"

/// Bundle identifier of the main app. The helper uses this as part of the
/// code-signing requirement when validating inbound connections — only the
/// real Wall app, signed by the same team, can talk to the helper.
public let WallMainAppBundleID = "design.wooj.wall"

/// Apple Developer team ID for code-signing requirement.
public let WallTeamID = "BSPX8X9U4B"

/// XPC interface between Wall and its privileged helper.
/// Replies use `String?` — nil for success, error message for failure.
/// Keeping the wire format simple avoids NSError bridging quirks across
/// the XPC boundary.
@objc(WallHelperProtocol) public protocol WallHelperProtocol {
    func block(maxSeconds: Int, withReply reply: @escaping (String?) -> Void)
    func unblock(withReply reply: @escaping (String?) -> Void)
    func ping(withReply reply: @escaping (String) -> Void)
}
