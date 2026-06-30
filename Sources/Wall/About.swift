import SwiftUI
import AppKit
import WoojTokens

/// App version, read from the bundle's Info.plist (written by build-app.sh).
/// Falls back to "dev" when run unbundled (e.g. `swift run`) where there's no
/// Info.plist to read.
enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    /// "0.1.0 (12)" — marketing version with the build number in parens.
    /// The build number is dropped for unbundled dev runs.
    static var display: String {
        short == "dev" ? "dev" : "\(short) (\(build))"
    }
}

/// About window — app icon, wordmark, version, one quiet line of identity.
/// Opened from the standard "About Wall" app-menu item (see WallApp commands).
struct AboutView: View {
    var body: some View {
        VStack(spacing: WoojSpace.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Wall").wallTitle()

            Text("Version \(AppVersion.display)")
                .font(WoojType.mono.font)
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)

            Text("A wall for focused writing.")
                .font(WoojType.body.font)
                .foregroundStyle(Palette.secondary)

            Link("woojdesign/Wall", destination: URL(string: "https://github.com/woojdesign/Wall")!)
                .font(WoojType.label.font)
                .foregroundStyle(Palette.clay)
        }
        .padding(WoojSpace.xl)
        .frame(width: 320)
        .background(Palette.ground)
    }
}
