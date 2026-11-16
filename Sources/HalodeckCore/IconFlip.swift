import Foundation

/// How Halodeck's icon comes into the notch greeting at launch: it flips in on
/// its vertical axis like a coin, growing from small, swings a little past face-on, then settles.
public enum IconFlip {
    public static let duration = 1.0

    /// The icon `t` seconds after it starts to come in. Reduce Motion only fades it in.
    public static func pose(at t: Double, reduceMotion: Bool = false) -> IconPose {
        if reduceMotion { return IconPose(rotationY: 0, scale: 1, opacity: min(1, max(0, t) / 0.2)) }
        guard t > 0 else { return IconPose(rotationY: -540, scale: 0.4, opacity: 0) }   // where the flip starts
        guard t < duration else { return .rest }
        let p = t / duration
        let turn = 1 - pow(1 - min(1, p / 0.8), 3)
        let settle = (p - 0.8) / 0.2
        let rotation = p < 0.8 ? -540 + 560 * turn
            : 20 * (1 - (settle < 0.5 ? 2 * settle * settle : 1 - pow(-2 * settle + 2, 2) / 2))
        return IconPose(rotationY: rotation, scale: 0.4 + 0.6 * turn, opacity: min(1, p / 0.2))
    }
}

/// Rotation about the vertical axis in degrees, scale and opacity.
public struct IconPose: Equatable, Sendable {
    public var rotationY: Double
    public var scale: Double
    public var opacity: Double

    public static let rest = IconPose(rotationY: 0, scale: 1, opacity: 1)
}
