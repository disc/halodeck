@testable import HalodeckCore

/// Shared fixtures: a 142.7 × 85.1 mm trackpad, 10% strips, 4 mm per step.
enum Pad {
    static let width = 142.7
    static let height = 85.1
}

func config(
    swipe: Bool = true,
    sides: [Side: SideAction] = [.left: .brightness, .right: .volume],
    corners: Set<Corner> = [.topLeft],
    step: Double = 4.0,
    horizontalSwipe: Bool = false
) -> RecognizerConfig {
    // swipe = the left and right sides start without a click; horizontalSwipe adds top and bottom.
    var swipeSides: Set<Side> = swipe ? [.left, .right] : []
    if horizontalSwipe && swipe { swipeSides.formUnion([.top, .bottom]) }
    return RecognizerConfig(swipeSides: swipeSides,
                            layout: ZoneLayout(sideWidthFraction: 0.10),
                            slidePerStepMM: step,
                            activeSides: sides,
                            activeCorners: corners)
}

func touch(_ id: Int32 = 1, x: Double, y: Double) -> TouchPoint {
    TouchPoint(id: id, normalizedX: x, xMM: x * Pad.width, yMM: y)
}

func frame(_ touches: [TouchPoint], t: Double = 0, device: Int = 1) -> TouchFrame {
    TouchFrame(device: device, padHeightMM: Pad.height, touches: touches, time: t)
}

/// Normalised x after moving `mm` sideways from `x`.
func shifted(_ x: Double, byMM mm: Double) -> Double { x + mm / Pad.width }

func resting(x: Double, y: Double = 40, _ cfg: RecognizerConfig = config()) -> Recognizer {
    var r = Recognizer(config: cfg)
    _ = r.touchFrame(frame([touch(x: x, y: y)]))
    return r
}
