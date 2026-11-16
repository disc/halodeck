/// A muted sign beside the notch: sound off (muted or at 0%) or a microphone muted with Halodeck.
public enum MuteSignKind: CaseIterable, Hashable, Sendable {
    case sound, microphone
}

/// Which muted signs go in the ear left of the notch and which in the ear right of it, each in screen
/// order (left to right).
public struct MuteSignsLayout: Equatable, Sendable {
    public let left: [MuteSignKind]
    public let right: [MuteSignKind]

    public init(left: [MuteSignKind], right: [MuteSignKind]) {
        self.left = left
        self.right = right
    }

    public var isEmpty: Bool { left.isEmpty && right.isEmpty }
}

extension MuteSignsSide {
    /// Where the signs for what is muted go on this side setting: the microphone's is always the
    /// outermost when both share an ear.
    public func layout(sound: Bool, microphone: Bool) -> MuteSignsLayout {
        let shown = MuteSignKind.allCases.filter { $0 == .sound ? sound : microphone }
        switch self {
        case .right: return MuteSignsLayout(left: [], right: shown)
        case .left: return MuteSignsLayout(left: shown.reversed(), right: [])
        }
    }
}
