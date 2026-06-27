import SwiftUI
import WoojTokens

// Wall is on the shared Wooj design system (wooj-tokens). The local color /
// spacing / type tokens that used to live here are gone — call sites use
// `WoojColor` / `WoojSpace` / `WoojType` / `WoojMotion` directly. What stays
// are thin role helpers (so views read as intent) and Wall's two button
// styles, both now expressed in Wooj values.
//
// Note: wooj-tokens is light-only today, so Wall runs light-only (the root
// views pin `.preferredColorScheme(.light)`). Dark mode returns when the
// token set grows dark variants.

// MARK: - Typography roles

extension View {
    /// Uppercase, tracked metadata label — the "WALL" wordmark, gate captions.
    func wallLabel() -> some View {
        self.font(WoojType.label.font)
            .tracking(WoojType.label.tracking)
            .textCase(.uppercase)
            .foregroundStyle(WoojColor.tertiary)
    }

    /// Section headline — Charter (serif). Wall's *voice* is the reading
    /// serif; the chrome (labels, counts, buttons) stays Geist. wooj-tokens
    /// has a single serif role (`reading`/Charter 21), so this borrows the
    /// `title` scale until a serif-title token lands upstream (requested).
    func wallTitle() -> some View {
        self.font(.custom("Charter", fixedSize: WoojType.title.size))
            .tracking(WoojType.title.tracking)
            .foregroundStyle(WoojColor.ink)
    }

    /// Reading copy — Charter, the long-form serif (intro + done-screen voice).
    func wallBody() -> some View {
        self.font(WoojType.reading.font)
            .tracking(WoojType.reading.tracking)
            .foregroundStyle(WoojColor.reading)
            .lineSpacing(WoojType.reading.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

/// Primary action — the one confident clay pill (Begin).
struct WallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WoojType.label.font)
            .tracking(WoojType.label.tracking)
            .foregroundStyle(WoojColor.onClay)
            .padding(.vertical, WoojSpace.md)
            .padding(.horizontal, WoojSpace.lg)
            .frame(maxWidth: .infinity)
            .background(
                configuration.isPressed ? WoojColor.clayPressed : WoojColor.clay,
                in: Capsule()
            )
            .animation(WoojMotion.calm.animation, value: configuration.isPressed)
    }
}

/// Quiet secondary — hairline-bordered pill (New session, Finish).
struct WallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WoojType.label.font)
            .tracking(WoojType.label.tracking)
            .foregroundStyle(WoojColor.ink)
            .padding(.vertical, WoojSpace.md)
            .padding(.horizontal, WoojSpace.lg)
            .frame(maxWidth: .infinity)
            .background(WoojColor.surface.opacity(configuration.isPressed ? 0.7 : 0), in: Capsule())
            .overlay(Capsule().stroke(WoojColor.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(WoojMotion.calm.animation, value: configuration.isPressed)
    }
}

// MARK: - Copy affordance with confirmation

/// A quiet text link that copies and briefly confirms with "Copied".
/// Same wallLabel styling so it slots into any utility row without competing
/// with the primary action. The text is read at click time, so the caller
/// doesn't have to materialize it until then.
struct CopyLink: View {
    let title: String
    let text: () -> String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            WallActions.copyToClipboard(text())
            copied = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.4))
                if !Task.isCancelled {
                    copied = false
                }
            }
        } label: {
            Text(copied ? "Copied" : title)
                .wallLabel()
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .animation(WoojMotion.calm.animation, value: copied)
    }
}
