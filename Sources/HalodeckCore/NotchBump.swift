import Foundation

/// The bump when a level slide runs into 0% or 100%: the side of the notch the slide pushed against
/// (the right one at 100%, the left at 0%) stretches outward and springs back, overshooting a little,
/// while at 100% its bottom corner lights up quickly and fades. At 0% the gauge line is empty, so the
/// bump there is the push alone, with no light.
public struct NotchBump: Equatable, Sendable {
    /// How long the push lasts, and how far it reaches at its peak (points).
    public static let pushDuration: TimeInterval = 0.42
    public static let reach = 6.0
    /// How far it springs back past rest before settling (points, negative = inward).
    public static let overshoot = -0.5
    /// How long the corner light lasts; it is brightest `lightRise` of the way through.
    public static let lightDuration: TimeInterval = 0.6
    public static let lightRise = 0.15

    public let start: Date
    /// True when the slide ran into 100% (up/right).
    public let top: Bool

    public init(at start: Date, top: Bool) {
        self.start = start
        self.top = top
    }

    public var right: Bool { top }

    /// How far the pushed side stands out of its rest position at `date`, in points; 0 with Reduce Motion.
    public func push(at date: Date, reduceMotion: Bool = false) -> Double {
        let u = date.timeIntervalSince(start) / Self.pushDuration
        guard !reduceMotion, u > 0, u < 1 else { return 0 }
        // Each stretch eases in and out of its ends, so the motion has no jolts.
        func ease(_ a: Double, _ b: Double, _ v: Double) -> Double { a + (b - a) * (1 - cos(.pi * v)) / 2 }
        switch u {
        case ..<0.35: return Self.reach * sin(u / 0.35 * .pi / 2)
        case ..<0.7: return ease(Self.reach, Self.overshoot, (u - 0.35) / 0.35)
        default: return ease(Self.overshoot, 0, (u - 0.7) / 0.3)
        }
    }

    /// How bright the corner light is at `date`, 0...1; always 0 at 0%.
    public func light(at date: Date) -> Double {
        guard top else { return 0 }
        let u = date.timeIntervalSince(start) / Self.lightDuration
        guard u > 0, u < 1 else { return 0 }
        if u < Self.lightRise {
            let v = u / Self.lightRise
            return v * (2 - v)
        }
        let w = (u - Self.lightRise) / (1 - Self.lightRise)
        return (1 - w) * (1 - w)
    }

    public func isOver(at date: Date) -> Bool {
        date.timeIntervalSince(start) >= (top ? max(Self.pushDuration, Self.lightDuration) : Self.pushDuration)
    }
}
