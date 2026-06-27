import SwiftUI
import AppKit
import WoojTokens

struct MenuBarContent: View {
    @EnvironmentObject var model: SessionModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: WoojSpace.md) {
            switch model.phase {
            case .idle:
                Text("Wall").wallLabel()
                Text("The wall is down.")
                    .font(WoojType.body.font).foregroundStyle(WoojColor.ink)
            case .active:
                Text(statusLabel).wallLabel()
                ProgressView(value: model.progress).tint(WoojColor.ink)
                Text("\(model.count)/\(model.settings.wordTarget) \(model.settings.countMode.label)  ·  \(short)")
                    .font(WoojType.mono.font).monospacedDigit()
                    .foregroundStyle(WoojColor.secondary)
            case .complete:
                Text("Wall").wallLabel()
                Text("You're back.")
                    .font(WoojType.body.font).foregroundStyle(WoojColor.ink)
            }

            // Pull the last writing without opening the window. Not shown
            // mid-session — during .active you should be on the wall, not
            // reaching back to past ones.
            if model.phase != .active, let last = WallActions.mostRecentWriting() {
                HStack(spacing: WoojSpace.xs) {
                    CopyLink(title: "Copy last", text: { WallActions.contents(of: last) })
                    Text("·").wallLabel()
                    Button(action: { WallActions.revealInFinder(last) }) {
                        Text("Reveal").wallLabel()
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.vertical, 2)

            Button("Open Wall") {
                openWindow(id: "wall")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain).foregroundStyle(WoojColor.secondary)

            Button("About Wall") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain).foregroundStyle(WoojColor.secondary)

            CheckForUpdatesButton()
                .foregroundStyle(WoojColor.secondary)

            Button("Quit Wall") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(WoojColor.secondary)

            Text("Wall \(AppVersion.display)")
                .font(WoojType.caption.font)
                .foregroundStyle(WoojColor.tertiary)
                .padding(.top, WoojSpace.xxs)
        }
        .padding(WoojSpace.md)
        .frame(width: 260, alignment: .leading)
        .preferredColorScheme(.light)
    }

    private var statusLabel: String {
        if model.released { return "The wall is down · keep writing" }
        return model.settings.keepOnline ? "Wall is up · online" : "Wall is up"
    }

    private var short: String {
        let s = Int(model.timeRemaining)
        return model.timeGateMet ? "time met" : String(format: "%d:%02d left", s / 60, s % 60)
    }
}
