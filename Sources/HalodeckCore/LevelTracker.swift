import Foundation

/// Decides how many steps deserve a haptic tick: none once the level is at 0% or 100% in the
/// direction of travel. The system applies posted keys a moment later, so during a slide it tracks
/// its own predicted level and only re-reads the real one after a pause of `staleAfter` seconds.
public struct LevelTracker: Sendable {
    private let staleAfter: TimeInterval
    private var predicted: [SideAction: (level: Double, at: TimeInterval)] = [:]

    /// The steps of one call: the level before them (predicted or read; nil if unknown) and one
    /// entry per step that deserves a tick, the level right after that step.
    public struct Steps: Sendable, Equatable {
        public var start: Double?
        public var tickLevels: [Double?]
    }

    public init(staleAfter: TimeInterval = 0.3) {
        self.staleAfter = staleAfter
    }

    public mutating func steps(for steps: Int, step: LevelStep, function: SideAction,
                               now: TimeInterval, read: () -> Double?) -> Steps {
        let start: Double?
        if let p = predicted[function], now - p.at < staleAfter {
            start = p.level
        } else {
            start = read()
        }
        guard var level = start else {
            predicted[function] = nil
            return Steps(start: nil, tickLevels: Array(repeating: nil, count: abs(steps)))
        }
        let up = steps > 0
        var levels: [Double?] = []
        for _ in 0..<abs(steps) {
            let atLimit = up ? level >= 0.999 : level <= 0.001
            level = step.next(from: level, up: up)
            if !atLimit { levels.append(level) }
        }
        predicted[function] = (level, now)
        return Steps(start: start, tickLevels: levels)
    }
}
