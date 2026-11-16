import Foundation

/// The streaks of "Every step": each step adds one, and each runs for its full `duration`
/// whatever comes after it, so a fast slide shows several streaks chasing each other round the notch.
public struct NotchStreaks: Equatable, Sendable {
    public struct Streak: Equatable, Sendable {
        public let start: Date
        /// +1 up/right (left to right along the outline), -1 down/left.
        public let direction: Int
    }

    /// A streak still running: how far along it is (0...1) and which way it goes.
    public struct Live: Equatable, Sendable {
        public let progress: Double
        public let direction: Int
    }

    public let duration: TimeInterval
    /// The most streaks kept at once; a very fast slide keeps only the newest.
    public let limit: Int
    private var streaks: [Streak] = []

    public init(duration: TimeInterval, limit: Int = 6) {
        self.duration = duration
        self.limit = limit
    }

    public var count: Int { streaks.count }

    public mutating func add(at date: Date, direction: Int) {
        streaks.removeAll { date.timeIntervalSince($0.start) >= duration }
        streaks.append(Streak(start: date, direction: direction >= 0 ? 1 : -1))
        if streaks.count > limit { streaks.removeFirst(streaks.count - limit) }
    }

    /// The streaks running at `date`, oldest first.
    public func live(at date: Date) -> [Live] {
        streaks.compactMap { s in
            let x = date.timeIntervalSince(s.start) / duration
            return x >= 0 && x < 1 ? Live(progress: x, direction: s.direction) : nil
        }
    }
}
