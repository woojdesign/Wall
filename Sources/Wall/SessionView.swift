import SwiftUI
import WoojTokens

struct SessionView: View {
    @EnvironmentObject var model: SessionModel

    // Charter (the reading serif) at the reading scale, bridged into AppKit for
    // the TextKit 2 surface. The caret takes Wall's clay accent.
    private var writingFont: NSFont {
        NSFont(name: WoojType.reading.family, size: WoojType.reading.size)
            ?? .systemFont(ofSize: WoojType.reading.size)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The writing surface — quiet, centered, no chrome. Charter, the
            // reading serif: in a writing app, what you produce is the prose.
            // The placeholder is drawn by the surface (so it sits where text
            // begins, mid-screen under typewriter scrolling).
            WritingSurface(
                text: $model.text,
                font: writingFont,
                textColor: Palette.inkNS,
                caretColor: Palette.clayNS,
                lineSpacing: WoojType.reading.lineSpacing,
                placeholder: "what's here right now?",
                dimColor: Palette.mutedNS
            )
            .onChange(of: model.text) { model.textChanged() }
            .frame(maxWidth: 640)
            .padding(.horizontal, WoojSpace.xxl)
            // Small top margin so text can scroll near the top of the window —
            // a big gap looked silly, especially in full-screen immersion. The
            // session start is centered by the surface's own typewriter inset,
            // independent of this.
            .padding(.top, WoojSpace.lg)
            .padding(.bottom, WoojSpace.xl)

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: WoojSpace.md) {
            if model.released {
                released
            } else {
                if !hint.isEmpty {
                    Text(hint).wallLabel()
                        .transition(.opacity)
                }
                progressBar
            }

            countsRow
        }
        .padding(.horizontal, WoojSpace.xxl)
        .padding(.bottom, WoojSpace.xl)
        .frame(maxWidth: 640)
        .animation(WoojMotion.calm.animation, value: hint)
        .animation(WoojMotion.calm.animation, value: model.released)
    }

    // Both gates cleared: invite continuing, offer the exit.
    private var released: some View {
        VStack(spacing: WoojSpace.sm) {
            Text("The wall is down — keep going, or finish when you're ready.")
                .font(WoojType.label.font)
                .tracking(WoojType.label.tracking)
                .foregroundStyle(Palette.tertiary)
                .multilineTextAlignment(.center)
            Button("I'm done") { model.finish() }
                .buttonStyle(WallSecondaryButtonStyle())
                .frame(width: 200)
        }
        .transition(.opacity)
    }

    // Ambient progress — the lagging gate fills the line.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.line)
                Rectangle().fill(Palette.ink.opacity(0.3))
                    .frame(width: geo.size.width * model.progress)
                    .animation(WoojMotion.calm.animation, value: model.progress)
            }
        }
        .frame(height: 2)
    }

    // Live word/char count + timer — Geist Mono, tabular, calm.
    private var countsRow: some View {
        HStack {
            Text("\(model.count) / \(model.settings.wordTarget) \(model.settings.countMode.label)")
                .font(WoojType.mono.font)
                .monospacedDigit()
                .foregroundStyle(model.wordGateMet ? Palette.secondary : Palette.tertiary)
            Spacer()
            Text(timeString)
                .font(WoojType.mono.font)
                .monospacedDigit()
                .foregroundStyle(model.timeGateMet ? Palette.secondary : Palette.tertiary)
        }
    }

    private var hint: String {
        // Online sessions show the mode marker always — there's no "back
        // online" narrative to tell when you never went offline.
        if model.settings.keepOnline { return "online session" }
        switch (model.timeGateMet, model.wordGateMet) {
        case (false, true): return "Words met · back online when the time is served"
        case (true, false): return "A little more writing to reconnect"
        default: return ""
        }
    }

    private var timeString: String {
        let s = Int(model.timeRemaining)
        return model.timeGateMet ? "time met" : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct DoneView: View {
    @EnvironmentObject var model: SessionModel

    var body: some View {
        VStack(spacing: WoojSpace.lg) {
            Text("Wall").wallLabel()
            Text("You're back.").wallTitle()
            Text("The wall is down. Your writing is saved to \(Storage.displayLocation).")
                .wallBody()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Point to where it can be read back, at the moment it matters most.
            Button { Navigation.shared.tab = .archive } label: {
                (Text("Read it back anytime in the ").foregroundColor(Palette.tertiary)
                    + Text("Archive").foregroundColor(Palette.clay))
                    .font(WoojType.label.font)
                    .tracking(WoojType.label.tracking)
            }
            .buttonStyle(.plain)

            // Quiet exits: take the text with you, or find the file.
            // Placed before the primary action so you see them before committing
            // to "begin again", but styled to recede.
            HStack(spacing: WoojSpace.md) {
                CopyLink(title: "Copy writing", text: { model.text })
                Text("·").wallLabel()
                Button(action: {
                    if let url = WallActions.mostRecentWriting() {
                        WallActions.revealInFinder(url)
                    }
                }) {
                    Text("Reveal file").wallLabel()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, WoojSpace.xs)

            Button("New session") { model.startNewSession() }
                .buttonStyle(WallSecondaryButtonStyle())
                .frame(width: 220)
                .padding(.top, WoojSpace.md)
        }
        .padding(WoojSpace.xxxl)
    }
}
