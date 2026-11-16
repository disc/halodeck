import Foundation

/// Corner bursts: a corner click sends a burst of light out from the notch's matching corner (left or
/// right; top corners from where the notch meets the screen's edge, bottom ones from its bottom
/// corner); a double click sends a second one `spacing` later. Each burst lasts `duration`.
public struct NotchBursts: Equatable, Sendable {
    public struct Live: Equatable, Sendable {
        public let left: Bool
        public let top: Bool
        /// 0...1 through the burst.
        public let progress: Double
    }

    private struct Burst: Equatable, Sendable {
        let start: Date
        let left: Bool
        let top: Bool
    }

    public let duration: TimeInterval
    public let spacing: TimeInterval
    private var bursts: [Burst] = []

    public init(duration: TimeInterval, spacing: TimeInterval) {
        self.duration = duration
        self.spacing = spacing
    }

    public var count: Int { bursts.count }

    public mutating func add(left: Bool, top: Bool, clicks: Int, at date: Date) {
        bursts.removeAll { date.timeIntervalSince($0.start) >= duration }
        for i in 0..<max(1, clicks) {
            bursts.append(Burst(start: date.addingTimeInterval(Double(i) * spacing), left: left, top: top))
        }
    }

    public func live(at date: Date) -> [Live] {
        bursts.compactMap { b in
            let x = date.timeIntervalSince(b.start) / duration
            return x >= 0 && x < 1 ? Live(left: b.left, top: b.top, progress: x) : nil
        }
    }
}
