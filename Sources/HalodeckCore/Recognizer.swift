import Foundation

public struct TouchPoint: Equatable, Sendable {
    public var id: Int32
    public var normalizedX: Double
    public var xMM: Double
    public var yMM: Double

    public init(id: Int32, normalizedX: Double, xMM: Double, yMM: Double) {
        self.id = id; self.normalizedX = normalizedX; self.xMM = xMM; self.yMM = yMM
    }
}

/// All fingers currently touching one trackpad (state "make touch" or "touching" only).
public struct TouchFrame: Equatable, Sendable {
    public var device: Int
    public var padHeightMM: Double
    public var touches: [TouchPoint]
    public var time: TimeInterval

    public init(device: Int, padHeightMM: Double, touches: [TouchPoint], time: TimeInterval) {
        self.device = device; self.padHeightMM = padHeightMM; self.touches = touches; self.time = time
    }
}

public struct RecognizerConfig: Equatable, Sendable {
    /// Sides that may start a gesture without a click (any side always works with press-and-slide).
    public var swipeSides: Set<Side>
    public var layout: ZoneLayout
    public var slidePerStepMM: Double
    /// Only sides whose function is switched on and usable (the Engine decides).
    public var activeSides: [Side: SideAction]
    /// Corners that have an action, when corners are switched on.
    public var activeCorners: Set<Corner>
    public var swipeStartMM: Double
    /// A gesture ends if its trackpad sends no frame for this long (disconnected, asleep).
    public var silenceLimit: TimeInterval
    /// Top/bottom sides in `swipeSides` start without a click only for a finger that lands within
    /// `horizontalSwipeBandMM` of the border and slides clearly sideways
    /// (`Recognizer.horizontalSwipeAxisRatio`).
    public var horizontalSwipeBandMM: Double

    public init(swipeSides: Set<Side>, layout: ZoneLayout, slidePerStepMM: Double,
                activeSides: [Side: SideAction], activeCorners: Set<Corner>,
                swipeStartMM: Double = 3.0, silenceLimit: TimeInterval = 0.25,
                horizontalSwipeBandMM: Double = 4.0) {
        self.swipeSides = swipeSides; self.layout = layout; self.slidePerStepMM = slidePerStepMM
        self.activeSides = activeSides; self.activeCorners = activeCorners
        self.swipeStartMM = swipeStartMM; self.silenceLimit = silenceLimit
        self.horizontalSwipeBandMM = horizontalSwipeBandMM
    }
}

public enum RecognizerOutput: Equatable, Sendable {
    case gestureBegan(side: Side, function: SideAction, device: Int, finger: Int32)
    /// Positive = up (more).
    case steps(function: SideAction, count: Int)
    case gestureEnded
    case cornerAction(Corner)
    /// Post the held mouse-down followed by a mouse-up.
    case replayHeldClick
    /// Post the held mouse-down; later events pass through.
    case releaseHeldDown
}

public enum MouseDownDecision: Equatable, Sendable { case pass, swallow, hold }

/// Pure state machine that turns trackpad touches and mouse clicks into gestures and corner clicks.
public struct Recognizer: Sendable {
    /// A held click becomes a slide along a side once the finger has moved at least this many
    /// times more along that side than across it.
    static let heldSlideAxisRatio = 2.0
    /// A left or right side swipe without a click: at least this many times more up/down than sideways.
    static let sideSwipeAxisRatio = 2.0
    /// A top/bottom swipe without a click: at least this many times more sideways than up/down,
    /// so ordinary pointing rarely triggers it.
    static let horizontalSwipeAxisRatio = 3.0

    private struct Finger: Sendable {
        var landX: Double, landXMM: Double, landYMM: Double
        var x: Double, xMM: Double, yMM: Double
        var rejected = false
    }

    private struct Gesture: Sendable {
        var device: Int, finger: Int32
        var side: Side, function: SideAction
        var anchorMM: Double
    }

    /// A mouse-down held back while Halodeck waits to see whether a slide follows. It is never handed
    /// to the app on a timer: a slow slide must not turn into a text selection in the app underneath.
    private struct Hold: Sendable {
        var device: Int, finger: Int32
        /// Active sides the click is inside: the slide direction picks one.
        var sides: Set<Side>, corner: Corner?
        var startXMM: Double, startYMM: Double
        /// A corner click whose finger moved off without starting a slide: cancelled, and swallowed.
        var wandered = false
    }

    private var config: RecognizerConfig
    private var fingers: [Int: [Int32: Finger]] = [:]
    private var padHeights: [Int: Double] = [:]
    private var gesture: Gesture?
    /// At most one of `gesture` and `hold` exists at a time, across all trackpads.
    private var hold: Hold?
    /// The current click (down already swallowed or turned into a gesture): swallow its drags and up.
    private var swallowingClick = false
    /// The current click's mouse-down already reached the app: no swipe may take it over until mouse-up.
    private var buttonPassed = false
    private var lastFrameTime: [Int: TimeInterval] = [:]

    public init(config: RecognizerConfig) {
        self.config = config
    }

    public var isGestureActive: Bool { gesture != nil }

    public mutating func update(config newConfig: RecognizerConfig) -> [RecognizerOutput] {
        config = newConfig
        if let g = gesture, newConfig.activeSides[g.side] != g.function {
            return endGesture()
        }
        return []
    }

    public mutating func touchFrame(_ frame: TouchFrame) -> [RecognizerOutput] {
        padHeights[frame.device] = frame.padHeightMM
        lastFrameTime[frame.device] = frame.time
        let previous = fingers[frame.device] ?? [:]
        var current: [Int32: Finger] = [:]
        for t in frame.touches {
            if var f = previous[t.id] {
                f.x = t.normalizedX; f.xMM = t.xMM; f.yMM = t.yMM
                current[t.id] = f
            } else {
                current[t.id] = Finger(landX: t.normalizedX, landXMM: t.xMM, landYMM: t.yMM,
                                       x: t.normalizedX, xMM: t.xMM, yMM: t.yMM)
            }
        }
        if current.count > 1 {
            for id in current.keys { current[id]?.rejected = true }
        }
        fingers[frame.device] = current

        // While a click is held, only its own trackpad may turn it into a gesture: a swipe on
        // another trackpad would be replaced by the click's gesture, or run on after its replay.
        if let h = hold {
            return h.device == frame.device ? holdFrame(current) : []
        }

        if var g = gesture {
            guard g.device == frame.device else { return [] }
            guard let f = current[g.finger] else { return endGesture() }
            let stepMM = config.slidePerStepMM * g.function.stepScale
            let position = g.side.isVertical ? f.yMM : f.xMM   // up / right = more
            let count = Int((position - g.anchorMM) / stepMM)
            guard count != 0 else { return [] }
            g.anchorMM += Double(count) * stepMM
            gesture = g
            return [.steps(function: g.function, count: count)]
        }

        guard !config.swipeSides.isEmpty else { return [] }
        return detectSwipe(device: frame.device)
    }

    public mutating func reset() -> [RecognizerOutput] {
        // Fingers still resting on the pad must not restart a gesture by themselves.
        for device in fingers.keys {
            for id in fingers[device, default: [:]].keys { fingers[device]?[id]?.rejected = true }
        }
        var out: [RecognizerOutput] = []
        if hold != nil {
            hold = nil
            out.append(.releaseHeldDown)
        }
        swallowingClick = false
        buttonPassed = false
        if gesture != nil { out += endGesture() }
        return out
    }

    public var isHolding: Bool { hold != nil }

    public mutating func mouseDown() -> MouseDownDecision {
        if gesture != nil {
            swallowingClick = true
            return .swallow
        }
        swallowingClick = false
        buttonPassed = false
        guard let (device, id, f) = singleFinger(),
              let padHeight = padHeights[device] else { return passClick() }

        let landCorner = config.layout.corner(normalizedX: f.landX, yMM: f.landYMM, padHeightMM: padHeight)
        let nowCorner = config.layout.corner(normalizedX: f.x, yMM: f.yMM, padHeightMM: padHeight)
        let corner = (landCorner != nil && landCorner == nowCorner && config.activeCorners.contains(landCorner!))
            ? landCorner : nil

        let landSides = config.layout.sides(normalizedX: f.landX, yMM: f.landYMM, padHeightMM: padHeight)
        let nowSides = config.layout.sides(normalizedX: f.x, yMM: f.yMM, padHeightMM: padHeight)
        let sides = landSides.intersection(nowSides).filter { config.activeSides[$0] != nil }

        guard corner != nil || !sides.isEmpty else { return passClick() }
        hold = Hold(device: device, finger: id, sides: sides, corner: corner,
                    startXMM: f.xMM, startYMM: f.yMM)
        return .hold
    }

    /// True = swallow this drag event.
    public func mouseDragged() -> Bool {
        hold != nil || swallowingClick || gesture != nil
    }

    public mutating func mouseUp() -> (swallow: Bool, outputs: [RecognizerOutput]) {
        if let h = hold {
            hold = nil
            if h.wandered { return (true, []) }
            // The corner may have been switched off while the click was held: then it's a plain click.
            if let corner = h.corner, config.activeCorners.contains(corner) { return (true, [.cornerAction(corner)]) }
            return (true, [.replayHeldClick])
        }
        buttonPassed = false
        if swallowingClick || gesture != nil {
            swallowingClick = false
            return (true, [])
        }
        return (false, [])
    }

    private mutating func passClick() -> MouseDownDecision {
        buttonPassed = true
        return .pass
    }

    /// The held mouse-down goes to the app after all; its finger can no longer start a swipe.
    private mutating func releaseHold() -> [RecognizerOutput] {
        guard let h = hold else { return [] }
        hold = nil
        buttonPassed = true
        fingers[h.device]?[h.finger]?.rejected = true
        return [.releaseHeldDown]
    }

    /// Drops fingers and state from trackpads that are gone (disconnected, re-created after wake).
    public mutating func forgetDevices(notIn keep: Set<Int>) -> [RecognizerOutput] {
        var out: [RecognizerOutput] = []
        if let h = hold, !keep.contains(h.device) { out += releaseHold() }
        if let g = gesture, !keep.contains(g.device) { out += endGesture() }
        fingers = fingers.filter { keep.contains($0.key) }
        padHeights = padHeights.filter { keep.contains($0.key) }
        lastFrameTime = lastFrameTime.filter { keep.contains($0.key) }
        return out
    }

    /// Ends a gesture whose trackpad has gone silent for `silenceLimit`.
    public mutating func tick(time: TimeInterval) -> [RecognizerOutput] {
        var out: [RecognizerOutput] = []
        if let g = gesture, time - (lastFrameTime[g.device] ?? time) > config.silenceLimit { out += endGesture() }
        return out
    }

    private func singleFinger() -> (device: Int, id: Int32, finger: Finger)? {
        let touching = fingers.filter { !$0.value.isEmpty }
        guard touching.count == 1, let (device, list) = touching.first,
              list.count == 1, let (id, f) = list.first else { return nil }
        return (device, id, f)
    }

    /// While a click is held: a vertical slide on an active left or right side, or a horizontal slide
    /// on an active top or bottom side, becomes a gesture (the click is dropped). Any other movement,
    /// or a second finger, hands the mouse-down to the app (an ordinary drag) — except in a corner
    /// with an action, which keeps its click: a second finger is ignored and wandering off cancels it.
    private mutating func holdFrame(_ current: [Int32: Finger]) -> [RecognizerOutput] {
        guard let h = hold, !h.wandered else { return [] }
        let ownsClick = h.corner.map { config.activeCorners.contains($0) } ?? false
        guard current.count == 1, let f = current[h.finger] else {
            if current.isEmpty || ownsClick { return [] }   // lifted before mouse-up / resting thumb
            return releaseHold()
        }
        let dx = abs(f.xMM - h.startXMM), dy = abs(f.yMM - h.startYMM)
        guard max(dx, dy) >= config.swipeStartMM else { return [] }
        let candidate: Side?
        if dy >= Self.heldSlideAxisRatio * dx { candidate = h.sides.first { $0.isVertical } }
        else if dx >= Self.heldSlideAxisRatio * dy { candidate = h.sides.first { !$0.isVertical } }
        else { candidate = nil }
        if let side = candidate, let function = config.activeSides[side] {
            hold = nil
            swallowingClick = true
            gesture = Gesture(device: h.device, finger: h.finger, side: side, function: function,
                              anchorMM: side.isVertical ? f.yMM : f.xMM)
            return [.gestureBegan(side: side, function: function, device: h.device, finger: h.finger)]
        }
        if ownsClick {
            hold?.wandered = true
            return []
        }
        return releaseHold()
    }

    /// Starts a gesture for the single eligible finger on `device` once it has slid mostly vertically
    /// along the left or right side, or (for top/bottom sides in `swipeSides`) clearly sideways from the
    /// border; rejects it once it has moved in a direction that can't start one.
    private mutating func detectSwipe(device: Int) -> [RecognizerOutput] {
        guard !buttonPassed, let current = fingers[device], current.count == 1,
              let (id, f) = current.first, !f.rejected else { return [] }
        let dx = abs(f.xMM - f.landXMM), dy = abs(f.yMM - f.landYMM)

        let vertical = config.layout.side(normalizedX: f.landX)
            .flatMap { side in config.swipeSides.contains(side) ? side : nil }
            .flatMap { side in config.activeSides[side].map { (side, $0) } }
        if let (side, function) = vertical, dy >= config.swipeStartMM, dy >= Self.sideSwipeAxisRatio * dx {
            gesture = Gesture(device: device, finger: id, side: side, function: function, anchorMM: f.yMM)
            return [.gestureBegan(side: side, function: function, device: device, finger: id)]
        }

        var horizontal: (Side, SideAction)?
        if let padHeight = padHeights[device] {
            let band = config.horizontalSwipeBandMM
            let side: Side? = f.landYMM <= band ? .bottom : f.landYMM >= padHeight - band ? .top : nil
            horizontal = side.flatMap { s in config.swipeSides.contains(s) ? s : nil }
                .flatMap { s in config.activeSides[s].map { (s, $0) } }
        }
        if let (side, function) = horizontal, dx >= config.swipeStartMM, dx >= Self.horizontalSwipeAxisRatio * dy {
            gesture = Gesture(device: device, finger: id, side: side, function: function, anchorMM: f.xMM)
            return [.gestureBegan(side: side, function: function, device: device, finger: id)]
        }

        if dx >= config.swipeStartMM || (dy >= config.swipeStartMM && vertical == nil) {
            fingers[device]?[id]?.rejected = true
        }
        return []
    }

    private mutating func endGesture() -> [RecognizerOutput] {
        if let g = gesture { fingers[g.device]?[g.finger]?.rejected = true }
        gesture = nil
        return [.gestureEnded]
    }
}
