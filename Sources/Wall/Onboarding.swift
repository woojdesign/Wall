import SwiftUI
import WoojTokens

/// First-session confirmation — shown once, the first time someone taps Begin,
/// at the exact moment the wall is about to go up. This is Wall's onboarding:
/// contextual, not an upfront tour. We explain what's about to happen *when it
/// matters*, then never again.
///
/// Gated by `@AppStorage("hasBegunOnce")` in StartView. To see it again while
/// testing, run `scripts/reset-onboarding.sh` (clears the flag + relaunches).
///
/// Copy here is placeholder — Sean owns the final words (same as the home page).
struct FirstSessionSheet: View {
    let minutes: Int
    let target: Int
    let unit: String        // "words" / "characters"
    let keepOnline: Bool
    let onBegin: () -> Void
    let onCancel: () -> Void

    private var message: String {
        // Concrete, not hand-wavy: name the exact gates this session must clear.
        let gate = "until the \(minutes) minutes have elapsed AND you've written \(target.formatted()) \(unit)"
        return keepOnline
            ? "Remember, this session runs \(gate) — are you ready to start?"
            : "Remember, the internet will be down \(gate) — are you ready to start?"
    }

    var body: some View {
        ZStack {
            // Dim the start screen behind; tap-out cancels.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: WoojSpace.lg) {
                Text("Before your first session").wallLabel()

                Text(message)
                    .wallBody()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)

                HStack(spacing: WoojSpace.md) {
                    Button("Not yet", action: onCancel)
                        .buttonStyle(WallSecondaryButtonStyle())
                    Button("Begin", action: onBegin)
                        .buttonStyle(WallPrimaryButtonStyle())
                }
                .frame(maxWidth: 320)
                .padding(.top, WoojSpace.xs)
            }
            .padding(WoojSpace.xxl)
            .frame(maxWidth: 420)
            .background(WoojColor.ground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WoojColor.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
            .padding(WoojSpace.xxl)
        }
    }
}
