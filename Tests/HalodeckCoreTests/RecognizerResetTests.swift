import Testing
@testable import HalodeckCore

/// `reset()` (Halodeck switched off, sleep, the event tap restarting) leaves nothing half-done.
@Suite struct RecognizerResetTests {
    @Test func endsTheGestureAndTheRestingFingerCannotRestartIt() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)], t: 0.1))
        #expect(r.isGestureActive)
        #expect(r.reset() == [.gestureEnded])
        #expect(!r.isGestureActive)
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 60)], t: 0.2)) == [])
        #expect(!r.isGestureActive)
    }

    @Test func releasesAHeldClick() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        #expect(r.mouseDown() == .hold)
        #expect(r.reset() == [.releaseHeldDown])
        #expect(!r.isHolding)
        #expect(r.mouseUp() == (swallow: false, outputs: []))
    }

    @Test func stopsSwallowingTheCurrentClick() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)], t: 0.1))
        #expect(r.mouseDown() == .swallow)
        #expect(r.reset() == [.gestureEnded])
        #expect(r.mouseDragged() == false)
        #expect(r.mouseUp() == (swallow: false, outputs: []))
    }

    @Test func doesNothingWhenIdle() {
        var r = Recognizer(config: config())
        #expect(r.reset() == [])
    }

    @Test func aNewFingerSwipesAfterReset() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        _ = r.reset()
        _ = r.touchFrame(frame([], t: 0.1))
        _ = r.touchFrame(frame([touch(2, x: 0.95, y: 40)], t: 0.2))
        #expect(r.touchFrame(frame([touch(2, x: 0.95, y: 44)], t: 0.3)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 2)])
    }
}
