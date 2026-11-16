import Foundation

public enum LevelStep: Sendable, Equatable {
    /// A sixteenth, as the media keys step.
    case normal
    /// A quarter step (1/64), while the fine-control key is held.
    case fine
    /// An eighth, snapping to the eighths (0, 12.5%, 25%, … 100%), while the coarse-control key is held.
    case coarse

    /// With both keys held, fine control wins, as the more deliberate of the two.
    public static func chosen(isLevel: Bool, fine: Bool, coarse: Bool) -> LevelStep {
        guard isLevel else { return .normal }
        return fine ? .fine : coarse ? .coarse : .normal
    }

    public var size: Double {
        switch self {
        case .normal: 1.0 / 16
        case .fine: 1.0 / 64
        case .coarse: 1.0 / 8
        }
    }

    /// A level this close to an eighth counts as on it (half a fine step), so a level read back a
    /// little off (62% for 62.5%) moves a whole eighth.
    static let onEighthTolerance = 1.0 / 128

    public func next(from level: Double, up: Bool) -> Double {
        switch self {
        case .normal, .fine:
            return min(1, max(0, level + (up ? size : -size)))
        case .coarse:
            let eighths = level * 8
            let nearest = eighths.rounded()
            let target: Double
            if abs(eighths - nearest) <= Self.onEighthTolerance * 8 {
                target = nearest + (up ? 1 : -1)
            } else {
                target = up ? eighths.rounded(.up) : eighths.rounded(.down)
            }
            return min(8, max(0, target)) / 8
        }
    }

    /// The level `steps` steps on from `level` (negative steps go down).
    public func level(from level: Double, steps: Int) -> Double {
        var level = level
        for _ in 0..<abs(steps) { level = next(from: level, up: steps > 0) }
        return level
    }

    /// Media-key presses (a sixteenth each) for one step from `level`: one for a normal or fine step
    /// (fine keys carry Shift+Option); for a coarse step as many as reach the next eighth, or two
    /// when the level is unknown.
    public func keyPresses(from level: Double?, up: Bool) -> Int {
        guard self == .coarse else { return 1 }
        guard let level else { return 2 }
        return Int((abs(next(from: level, up: up) - level) * 16).rounded())
    }
}
