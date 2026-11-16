import AppKit
import HalodeckCore
import Observation

/// What the notch indicator shows, as times on the clock: `NotchIndicator` reads it in a TimelineView,
/// so the shape, its contents and the light always move together.
@MainActor
@Observable
final class NotchModel {
    static let growTime = 0.3, shrinkTime = 0.22, earTime = 0.2
    static let stepTime = 0.45

    var symbol = "speaker.wave.2.fill"
    /// An app icon shown instead of the symbol (Open app).
    var image: NSImage?
    var content: HUDContent = .level(0)
    var notchWidth: CGFloat = Metrics.defaultNotch.width
    var height: CGFloat = Metrics.defaultNotch.height
    var effect: NotchEffect = .levelGauge
    /// Reduce Motion: the shape fades in and out instead of growing, the bump doesn't push, and the
    /// lights glow in place instead of running.
    var reduceMotion = false
    /// When it started growing out, and when it started shrinking back (nil while open).
    var openedAt = Date.distantPast
    var closingAt: Date?
    var earFrom: CGFloat = 104
    var earTo: CGFloat = 104
    var earChangedAt = Date.distantPast
    var streaks = NotchStreaks(duration: NotchModel.stepTime)
    /// Level gauge: the comets of sides without a level, and the line of sides with one.
    var comets = NotchComets()
    var gauge = NotchGlide()
    var bursts = NotchBursts(duration: 0.9, spacing: 0.2)
    /// False for the bare notch that only hosts corner bursts.
    var showsContent = true
    /// The last time a slide ran into 0% or 100%.
    var bump: NotchBump?
    /// False once the panel is hidden: the timeline stops.
    var active = false

    func lightStep(at now: Date, direction: Int, content: HUDContent, opening: Bool) {
        switch effect {
        case .everyStep:
            streaks.add(at: now, direction: opening ? 1 : direction)
        case .levelGauge:
            if case .level(let v) = content {
                // Reduce Motion: the line stands at the new level instead of gliding there.
                if opening || reduceMotion { gauge.jump(to: v) } else { gauge.move(to: v, at: now) }
            } else {
                comets.add(at: now, direction: direction)
            }
        case .off:
            break
        }
    }

    /// The gauge takes the place of the segmented bar: the right ear shows the number.
    var levelAsNumber: Bool { effect == .levelGauge }

    /// 0 = the bare notch, 1 = fully grown.
    func openness(at date: Date) -> Double {
        let grow = 1 - pow(1 - min(1, max(0, date.timeIntervalSince(openedAt) / Self.growTime)), 3)
        guard let closingAt else { return grow }
        let x = min(1, max(0, date.timeIntervalSince(closingAt) / Self.shrinkTime))
        return grow * (1 - x * x)
    }

    /// The end-of-range bump at `date`, nil when none is playing: how much wider it makes the left and
    /// right ears (only the pushed side moves; nothing with Reduce Motion), which corner lights, and
    /// how brightly.
    func bump(at date: Date) -> (left: CGFloat, right: CGFloat, rightCorner: Bool, light: Double)? {
        guard let bump, !bump.isOver(at: date) else { return nil }
        let push = CGFloat(bump.push(at: date, reduceMotion: reduceMotion))
        return (bump.right ? 0 : push, bump.right ? push : 0, bump.right, bump.light(at: date))
    }

    func ear(at date: Date) -> CGFloat {
        let x = min(1, max(0, date.timeIntervalSince(earChangedAt) / Self.earTime))
        return earFrom + (earTo - earFrom) * (1 - pow(1 - x, 3))
    }
}
