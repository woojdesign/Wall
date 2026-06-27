import Foundation
import WallShared

// The privileged helper. Runs as root in the system launchd domain (managed
// by SMAppService from the main app). Its only job is to accept XPC calls
// from the signed Wall app and execute pfctl / launchctl commands directly,
// so the user doesn't see a Touch ID / password prompt for every begin/end.
//
// Security boundary: every inbound connection is gated by a code-signing
// requirement — only a binary signed with our team ID *and* matching the
// main app's bundle identifier is allowed to call these methods. Without
// that check, any process on the machine could ask the helper to flush pf.

let listener = NSXPCListener(machServiceName: WallHelperMachServiceName)
let delegate = HelperListenerDelegate()
listener.delegate = delegate
listener.resume()
delegate.beginIdleWatch()

NSLog("[WallHelper] listening on \(WallHelperMachServiceName)")
RunLoop.main.run()
