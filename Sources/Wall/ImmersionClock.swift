import SwiftUI
import WoojTokens

/// A quiet analog clock for full-screen sessions. Immersion hides the menu bar,
/// so the time goes with it — this gives it back without breaking flow: a faint
/// ring and two hands in the corner, no second hand, no ticking, updating once a
/// minute. You glance, you know, you keep writing. Opt-out in Settings
/// (`immersionClock`, default on).
struct ImmersionClock: View {
    var body: some View {
        // Repaint on the minute — the minute hand is the finest thing shown, so
        // there's nothing to animate between ticks. Cheap and motionless.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ClockFace(date: context.date)
        }
        .frame(width: 46, height: 46)
        .opacity(0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClockFace: View {
    let date: Date

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            // Faint ring.
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(WoojColor.line),
                lineWidth: 1
            )

            // Four orientation ticks (12 · 3 · 6 · 9) — enough to read the hands,
            // not a full dial.
            for i in 0..<4 {
                let a = Double(i) / 4 * 2 * .pi
                let sa = CGFloat(sin(a)), ca = CGFloat(cos(a))
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + sa * (r - 3.5), y: c.y - ca * (r - 3.5)))
                tick.addLine(to: CGPoint(x: c.x + sa * r, y: c.y - ca * r))
                ctx.stroke(tick, with: .color(WoojColor.line), lineWidth: 1)
            }

            // Time → hand angles. Hour hand carries the minute fraction so it sits
            // correctly between numbers.
            let cal = Calendar.current
            let hour = Double(cal.component(.hour, from: date) % 12)
            let minute = Double(cal.component(.minute, from: date))
            let minuteAngle = minute / 60 * 2 * .pi
            let hourAngle = (hour + minute / 60) / 12 * 2 * .pi

            func hand(_ angle: Double, length: CGFloat, color: Color, width: CGFloat) {
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + CGFloat(sin(angle)) * length,
                                      y: c.y - CGFloat(cos(angle)) * length))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand(hourAngle, length: r * 0.5, color: WoojColor.muted, width: 1.6)
            hand(minuteAngle, length: r * 0.78, color: WoojColor.secondary, width: 1.4)

            // Center pivot.
            let dot: CGFloat = 1.4
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)),
                with: .color(WoojColor.secondary)
            )
        }
    }
}
