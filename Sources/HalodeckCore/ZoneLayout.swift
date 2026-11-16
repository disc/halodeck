/// Where the side strips and corners sit on a trackpad.
/// x is normalised 0...1 (left to right); y is in millimetres from the bottom border.
public struct ZoneLayout: Equatable, Sendable {
    public var sideWidthFraction: Double
    public var cornerHeightMM: Double
    /// Height of the top and bottom strips; they reach at least `cornerHeightMM` so that every
    /// corner point also lies in its top or bottom side.
    public var horizontalStripMM: Double

    public init(sideWidthFraction: Double, cornerHeightMM: Double = 12.0, horizontalStripMM: Double = 10.0) {
        self.sideWidthFraction = sideWidthFraction
        self.cornerHeightMM = cornerHeightMM
        self.horizontalStripMM = horizontalStripMM
    }

    /// Every side strip containing the point; a corner belongs to the left or right side and to the
    /// top or bottom one.
    public func sides(normalizedX x: Double, yMM: Double, padHeightMM: Double) -> Set<Side> {
        var result: Set<Side> = []
        if let vertical = side(normalizedX: x) { result.insert(vertical) }
        let strip = max(horizontalStripMM, cornerHeightMM)
        if yMM >= padHeightMM - strip { result.insert(.top) }
        if yMM <= strip { result.insert(.bottom) }
        return result
    }

    public func side(normalizedX x: Double) -> Side? {
        if x >= 1 - sideWidthFraction { return .right }
        if x <= sideWidthFraction { return .left }
        return nil
    }

    public func corner(normalizedX x: Double, yMM: Double, padHeightMM: Double) -> Corner? {
        guard let side = side(normalizedX: x) else { return nil }
        if yMM >= padHeightMM - cornerHeightMM { return side == .left ? .topLeft : .topRight }
        if yMM <= cornerHeightMM { return side == .left ? .bottomLeft : .bottomRight }
        return nil
    }
}
