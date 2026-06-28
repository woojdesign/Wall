import SwiftUI
import AppKit

/// Immersion mode — when a session begins, the Wall window takes the whole
/// screen (native full-screen auto-hides the menu bar and Dock); when the
/// session ends, it returns to a window. iA Writer can *dim* distractions;
/// only Wall can *remove* them — the net is already down, the screen follows.
///
/// Opt-out lives in Settings (`immersiveSessions`, default on).

/// Grabs the hosting `NSWindow` so SwiftUI can drive full-screen transitions.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

extension View {
    /// Enter full-screen when `phase` becomes `.active`, leave when it isn't —
    /// but only if immersion is enabled. Idempotent: only toggles when the
    /// window's actual state differs from what the phase wants.
    func immersion(phase: SessionPhase) -> some View {
        modifier(ImmersionModifier(phase: phase))
    }
}

private struct ImmersionModifier: ViewModifier {
    let phase: SessionPhase
    @AppStorage("immersiveSessions") private var immersive = true
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor { window = $0 })
            .onChange(of: phase) { _, newPhase in sync(newPhase) }
    }

    private func sync(_ phase: SessionPhase) {
        guard immersive, let window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        let wantsFullScreen = (phase == .active)
        if wantsFullScreen != isFullScreen {
            window.toggleFullScreen(nil)
        }
    }
}
