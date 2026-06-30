import SwiftUI
import WoojTokens

struct StartView: View {
    @EnvironmentObject var model: SessionModel
    // First-run only: the first Begin shows a one-time confirmation of what the
    // wall does (contextual onboarding), then this latches and never returns.
    @AppStorage("hasBegunOnce") private var hasBegunOnce = false
    @State private var confirming = false

    private struct Preset: Identifiable, Equatable {
        let minutes: Int, words: Int
        var id: String { "\(minutes)-\(words)" }
    }
    // Calibrated to a real sustained pace of ~65 wpm (≈1000 words in 15 min),
    // with a gentle taper for longer blocks — so the word and time gates roughly
    // co-terminate instead of one going slack. Top block capped at 30 minutes.
    private let presets = [
        Preset(minutes: 15, words: 1000),
        Preset(minutes: 20, words: 1250),
        Preset(minutes: 30, words: 1750),
    ]

    var body: some View {
        VStack(spacing: WoojSpace.xl) {
            VStack(spacing: WoojSpace.md) {
                Text("Wall").wallLabel()
                Text("Step away from the noise.")
                    .wallTitle()
                Text("The internet goes quiet until the time is served and the words are written. Nothing to solve — just somewhere to put it down.")
                    .wallBody()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: WoojSpace.xs) {
                ForEach(presets) { p in
                    Chip(
                        title: "\(p.minutes)m · \(p.words)",
                        selected: model.settings.durationMinutes == p.minutes && model.settings.wordTarget == p.words
                    ) {
                        model.settings.durationMinutes = p.minutes
                        model.settings.wordTarget = p.words
                    }
                }
            }

            HStack(spacing: WoojSpace.xxl) {
                Dial(label: "Minutes", value: $model.settings.durationMinutes, step: 5, range: 5...180)
                Dial(label: model.settings.countMode.label.capitalized,
                     value: $model.settings.wordTarget, step: 50, range: 0...5000)
            }

            Picker("", selection: $model.settings.countMode) {
                ForEach(CountMode.allCases, id: \.self) { Text($0.label.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            Button("Begin") {
                if hasBegunOnce { model.begin() } else { confirming = true }
            }
                .buttonStyle(WallPrimaryButtonStyle())
                .frame(width: 240)
                .padding(.top, WoojSpace.xs)

            // Quiet opt-out from the network cut. Toggle below Begin so the
            // primary path stays "Wall = the wall." Reads as an offer until
            // tapped, then as a confirmation of current state.
            Button {
                model.settings.keepOnline.toggle()
            } label: {
                Text(model.settings.keepOnline ? "staying online" : "or stay online for this one")
                    .font(WoojType.label.font)
                    .foregroundStyle(Palette.tertiary)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
            .animation(WoojMotion.calm.animation, value: model.settings.keepOnline)
        }
        .padding(WoojSpace.xxl)
        .overlay {
            if confirming {
                FirstSessionSheet(
                    minutes: model.settings.durationMinutes,
                    target: model.settings.wordTarget,
                    unit: model.settings.countMode.label,
                    keepOnline: model.settings.keepOnline,
                    onBegin: { hasBegunOnce = true; confirming = false; model.begin() },
                    onCancel: { confirming = false }
                )
                .transition(.opacity)
            }
        }
        .animation(WoojMotion.calm.animation, value: confirming)
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WoojType.label.font)
                .tracking(WoojType.label.tracking)
                .foregroundStyle(selected ? Palette.ink : Palette.tertiary)
                .padding(.vertical, WoojSpace.xs)
                .padding(.horizontal, WoojSpace.md)
                .background(selected ? AnyShapeStyle(Palette.surface) : AnyShapeStyle(.clear), in: Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1).opacity(selected ? 1 : 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct Dial: View {
    let label: String
    @Binding var value: Int
    let step: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: WoojSpace.xs) {
            Text(label).wallLabel()
            HStack(spacing: WoojSpace.md) {
                StepButton(symbol: "minus") { value = max(range.lowerBound, value - step) }
                Text("\(value)")
                    .font(WoojType.display.font)
                    .tracking(WoojType.display.tracking)
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 96)
                    .contentTransition(.numericText())
                    .animation(WoojMotion.settle.animation, value: value)
                StepButton(symbol: "plus") { value = min(range.upperBound, value + step) }
            }
        }
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 32, height: 32)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
