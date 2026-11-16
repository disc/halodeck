import Foundation

/// The comet of the Level gauge light, on sides without a level. A step starts a comet; steps that
/// come in the same direction while it is in the first 60% of its run feed it instead (a longer
/// tail, a thicker line), so a fast slide shows one bold comet rather than a crowd of streaks.
/// Reversing, or stepping later, starts a new one; the old one finishes its run. At most two run.
public struct NotchComets: Equatable, Sendable {
    /// A comet still running: how far along it is (0...1), which way it goes, how long its tail is
    /// (a fraction of the edge) and how thick its line is (points).
    public struct Live: Equatable, Sendable {
        public let progress: Double
        public let direction: Int
        public let tail: Double
        public let lineWidth: Double
    }

    public static let duration: TimeInterval = 0.5
    /// The part of a comet's run during which steps feed it.
    public static let feedWindow = 0.6
    public static let limit = 2

    private struct Comet: Equatable, Sendable {
        let start: Date
        let direction: Int
        var fed: Int
    }
    private var comets: [Comet] = []

    public init() {}

    public mutating func add(at date: Date, direction: Int) {
        let direction = direction >= 0 ? 1 : -1
        comets.removeAll { date.timeIntervalSince($0.start) >= Self.duration }
        if let last = comets.last, last.direction == direction,
           date.timeIntervalSince(last.start) < Self.duration * Self.feedWindow {
            comets[comets.count - 1].fed += 1
        } else {
            comets.append(Comet(start: date, direction: direction, fed: 0))
            if comets.count > Self.limit { comets.removeFirst(comets.count - Self.limit) }
        }
    }

    /// The comets running at `date`, oldest first.
    public func live(at date: Date) -> [Live] {
        comets.compactMap { c in
            let x = date.timeIntervalSince(c.start) / Self.duration
            guard x >= 0 && x < 1 else { return nil }
            let fed = Double(c.fed)
            return Live(progress: x, direction: c.direction,
                        tail: min(0.7, 0.3 + 0.06 * fed), lineWidth: min(4, 2.5 + 0.2 * fed))
        }
    }
}

/// The Level gauge line: it glides to a new level (ease-out over `duration`) instead of jumping,
/// and a new level mid-glide starts from wherever the line is.
public struct NotchGlide: Equatable, Sendable {
    public static let duration: TimeInterval = 0.18

    private var from = 0.0
    private var to = 0.0
    private var changedAt = Date.distantPast

    public init() {}

    /// Puts the line at `level` at once (the notch has just opened).
    public mutating func jump(to level: Double) {
        from = level
        to = level
        changedAt = .distantPast
    }

    public mutating func move(to level: Double, at date: Date) {
        from = value(at: date)
        to = level
        changedAt = date
    }

    public func value(at date: Date) -> Double {
        let x = date.timeIntervalSince(changedAt) / Self.duration
        if x >= 1 { return to }
        let t = max(0, x)
        return from + (to - from) * (1 - pow(1 - t, 3))
    }
}
