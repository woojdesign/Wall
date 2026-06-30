import SwiftUI
import AppKit
import WoojTokens

/// Wall-local adaptive palette.
///
/// wooj-tokens is light-only, so dark mode lives here until the studio system
/// grows its own dark variants. Light values ARE the shared tokens (so light
/// mode stays pixel-for-pixel identical); dark values are Wall's own warm dark —
/// a warm near-black ground, warm off-white ink, never pure #000.
///
/// Each role resolves through a dynamic `NSColor` (keyed off the view's
/// effective appearance), exposed as a SwiftUI `Color`. The writing surface is
/// AppKit, so the few roles it needs are also exposed as `NSColor`.
enum Palette {
    // MARK: Dark values (warm, not pure black)
    private static let dGround      = hex(0x16140F)
    private static let dSurface     = hex(0x221F18)
    private static let dInk         = hex(0xECE7DB)
    private static let dReading     = hex(0xD8D3C7)
    private static let dSecondary   = hex(0xB0AB9F)
    private static let dTertiary    = hex(0x847F75)
    private static let dMuted       = hex(0x6F6B62)
    private static let dClay        = hex(0xD07A62)
    private static let dClayPressed = hex(0xB75F47)
    private static let dLine        = NSColor.white.withAlphaComponent(0.14)

    // MARK: Roles (SwiftUI)
    static let ground      = dual(NSColor(WoojColor.ground),      dGround)
    static let surface     = dual(NSColor(WoojColor.surface),     dSurface)
    static let ink         = dual(NSColor(WoojColor.ink),         dInk)
    static let reading     = dual(NSColor(WoojColor.reading),     dReading)
    static let secondary   = dual(NSColor(WoojColor.secondary),   dSecondary)
    static let tertiary    = dual(NSColor(WoojColor.tertiary),    dTertiary)
    static let muted       = dual(NSColor(WoojColor.muted),       dMuted)
    static let line        = dual(NSColor(WoojColor.line),        dLine)
    static let clay        = dual(NSColor(WoojColor.clay),        dClay)
    static let clayPressed = dual(NSColor(WoojColor.clayPressed), dClayPressed)
    static let onClay      = WoojColor.onClay   // cream text on the clay pill, same in both

    // MARK: Roles the writing surface needs (AppKit)
    static let inkNS   = dynamicNS(NSColor(WoojColor.ink),   dInk)
    static let clayNS  = dynamicNS(NSColor(WoojColor.clay),  dClay)
    static let mutedNS = dynamicNS(NSColor(WoojColor.muted), dMuted)

    // MARK: Helpers
    private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    private static func dynamicNS(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    private static func dual(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: dynamicNS(light, dark))
    }
}

/// The user's appearance preference, persisted under "appearance"
/// ("system" | "light" | "dark"). Applied app-wide via `NSApplication.appearance`
/// so every window — main, About, Settings, the menu-bar popover — and the
/// dynamic Palette colors all resolve to the same mode.
enum AppAppearance {
    static func apply(_ raw: String) {
        switch raw {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default:      NSApplication.shared.appearance = nil   // follow the system
        }
    }
}
