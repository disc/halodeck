import Foundation

public struct CornerClick: Equatable, Sendable {
    public var corner: Corner
    public var count: Int
    public init(corner: Corner, count: Int) { self.corner = corner; self.count = count }
}

/// Counts quick repeated clicks on a corner. A corner whose only action is for one click fires at
/// once; otherwise each click waits up to `interval` (the system double-click time) for another, and
/// the count fires when no further click comes or the corner's highest click count is reached.
public struct CornerClickCounter: Sendable {
    private var pending: (corner: Corner, count: Int, time: TimeInterval)?
    private var ready: [CornerClick] = []

    public init() {}

    /// True while a click is waiting for a possible next one, or a result hasn't been collected.
    public var isWaiting: Bool { pending != nil || !ready.isEmpty }

    /// Returns a finished click to act on now, if there is one.
    public mutating func click(_ corner: Corner, at time: TimeInterval, maxClicks: Int,
                               interval: TimeInterval) -> CornerClick? {
        var count = 1
        if let p = pending {
            if p.corner == corner && time - p.time <= interval {
                count = p.count + 1
            } else {
                ready.append(CornerClick(corner: p.corner, count: p.count))
            }
            pending = nil
        }
        if count >= max(1, maxClicks) {
            ready.append(CornerClick(corner: corner, count: count))
        } else {
            pending = (corner, count, time)
        }
        return ready.isEmpty ? nil : ready.removeFirst()
    }

    /// Call regularly while waiting. Returns a finished click once its waiting time has passed.
    public mutating func tick(now: TimeInterval, interval: TimeInterval) -> CornerClick? {
        if !ready.isEmpty { return ready.removeFirst() }
        guard let p = pending, now - p.time > interval else { return nil }
        pending = nil
        return CornerClick(corner: p.corner, count: p.count)
    }
}
