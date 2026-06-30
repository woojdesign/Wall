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
                    .font(WoojType.body.font).foregroundStyle(Palette.ink)
            case .active:
                Text(statusLabel).wallLabel()
                ProgressView(value: model.progress).tint(Palette.ink)
                Text("\(model.count)/\(model.settings.wordTarget) \(model.settings.countMode.label)  ·  \(short)")
                    .font(WoojType.mono.font).monospacedDigit()
                    .foregroundStyle(Palette.secondary)
            case .complete:
                Text("Wall").wallLabel()
                Text("You're back.")
                    .font(WoojType.body.font).foregroundStyle(Palette.ink)
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
            .buttonStyle(.plain).foregroundStyle(Palette.secondary)

            Button("Archive") {
                openWindow(id: "wall")
                Navigation.shared.tab = .archive
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.secondary)

            Button("About Wall") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.secondary)

            CheckForUpdatesButton()
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondary)

            Button("Quit Wall") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(Palette.secondary)

            Text("Wall \(AppVersion.display)")
                .font(WoojType.caption.font)
                .foregroundStyle(Palette.tertiary)
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
