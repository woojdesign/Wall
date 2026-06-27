import SwiftUI
import AppKit
import ServiceManagement
import WoojTokens

@main
struct WallApp: App {
    @StateObject private var model = SessionModel(blocker: BlockerFactory.make())
    // Boots Sparkle at launch (auto-update checks against the GitHub appcast).
    @StateObject private var updater = Updater.shared

    var body: some Scene {
        Window("Wall", id: "wall") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 480)
                .task {
                    // Idempotent — first-time call adds the background item;
                    // subsequent calls are no-ops once status == .enabled.
                    HelperManager.shared.registerIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    // User may have toggled approval in System Settings while
                    // Wall was inactive — re-poll so the banner state catches up.
                    HelperManager.shared.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 740)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            WallTrayIcon(isActive: model.phase == .active)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Tray icon — outlined square at rest, square split by a horizontal seam
/// when the wall is up. Echoes the app icon (whose seam is the wall) at
/// menu-bar scale.
///
/// Rendered as a template NSImage (drawn in black on transparent, then
/// flagged `isTemplate = true`) so the system inverts/tints it for the
/// menu bar's actual appearance — same contract SF Symbols use. SwiftUI
/// shapes don't get template treatment in MenuBarExtra labels, which is
/// why the earlier version was invisible.
struct WallTrayIcon: View {
    let isActive: Bool

    var body: some View {
        Image(nsImage: Self.makeImage(active: isActive))
    }

    private static func makeImage(active: Bool) -> NSImage {
        let container: CGFloat = 18
        let square: CGFloat = 14
        let stroke: CGFloat = 1.4
        let inset = (container - square) / 2

        let image = NSImage(size: NSSize(width: container, height: container),
                            flipped: false) { _ in
            NSColor.black.setStroke()
            let r = NSRect(x: inset, y: inset, width: square, height: square)
            let outline = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            outline.lineWidth = stroke
            outline.stroke()

            if active {
                // Seam at lower-third (60% from top → 40% from bottom in y-up coords).
                let seamY = r.minY + square * 0.4
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: r.minX + stroke, y: seamY))
                seam.line(to: NSPoint(x: r.maxX - stroke, y: seamY))
                seam.lineWidth = stroke
                seam.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct RootView: View {
    @EnvironmentObject var model: SessionModel

    var body: some View {
        ZStack {
            // Flat warm bone — the calm Wooj ground. (The old animated
            // gradient is retired; flag in the report if its drift is missed.)
            WoojColor.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                HelperBanner()
                phaseView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // wooj-tokens is light-only today; pin light so fixed warm values
        // aren't fighting a dark system appearance.
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var phaseView: some View {
        switch model.phase {
        case .idle: StartView()
        case .active: SessionView()
        case .complete: DoneView()
        }
    }
}

/// First-run banner. Visible only when the helper isn't `.enabled`, which
/// covers: helper never registered, registered-but-awaiting-user-approval,
/// helper missing from bundle. The "Open Settings" button drops the user
/// at System Settings → Login Items & Extensions → Background.
///
/// While the banner is up, PFBlocker silently falls back to the osascript
/// admin path — so the app still works mid-approval, just with the prompts
/// the helper is meant to eliminate.
struct HelperBanner: View {
    @ObservedObject private var helper = HelperManager.shared

    var body: some View {
        if helper.status != .enabled {
            HStack(spacing: WoojSpace.md) {
                Text(message)
                    .font(WoojType.body.font)
                    .foregroundStyle(WoojColor.secondary)
                Spacer()
                Button("Open Settings") {
                    helper.openLoginItemsSettings()
                }
                .buttonStyle(.plain)
                .font(WoojType.body.font)
                .foregroundStyle(WoojColor.clay)
            }
            .padding(.horizontal, WoojSpace.lg)
            .padding(.vertical, WoojSpace.xs)
            .frame(maxWidth: .infinity)
            .background(WoojColor.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WoojColor.line)
                    .frame(height: 1)
            }
        }
    }

    private var message: String {
        switch helper.status {
        case .requiresApproval:
            return "One-time setup: approve the background helper to skip password prompts."
        case .notRegistered:
            return "Background helper not installed."
        case .notFound:
            return "Helper missing from app bundle — rebuild needed."
        default:
            return ""
        }
    }
}
