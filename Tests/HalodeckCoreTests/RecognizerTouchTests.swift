import Testing
@testable import HalodeckCore

@Suite struct RecognizerTouchTests {
    @Test func swipeUpEmitsSteps() {
        var r = Recognizer(config: config())
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 40)])) == [])
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 43.5)])) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 52)])) == [.steps(function: .volume, count: 2)])
        #expect(r.isGestureActive)
    }

    @Test func swipeDownNegativeSteps() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 52)]))
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 48.5)])) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 40)])) == [.steps(function: .volume, count: -2)])
    }

    @Test func sidewaysFirstRejects() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        #expect(r.touchFrame(frame([touch(x: shifted(0.95, byMM: -4), y: 40)])) == [])
        #expect(r.touchFrame(frame([touch(x: shifted(0.95, byMM: -4), y: 50)])) == [])
        #expect(!r.isGestureActive)
    }

    @Test func twoFingersReject() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(1, x: 0.95, y: 40), touch(2, x: 0.05, y: 40)]))
        #expect(r.touchFrame(frame([touch(1, x: 0.95, y: 50), touch(2, x: 0.05, y: 50)])) == [])
        // Lifting one finger doesn't revive the other.
        #expect(r.touchFrame(frame([touch(1, x: 0.95, y: 60)])) == [])
    }

    @Test func landingOutsideStripIgnored() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.5, y: 40)]))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 50)])) == [])
    }

    @Test func liftEndsGesture() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)]))
        #expect(r.touchFrame(frame([])) == [.gestureEnded])
        #expect(!r.isGestureActive)
    }

    @Test func clickModeIgnoresSwipe() {
        var r = Recognizer(config: config(swipe: false))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 50)])) == [])
    }

    @Test func inactiveSideIgnored() {
        var r = Recognizer(config: config(sides: [.right: .volume]))
        _ = r.touchFrame(frame([touch(x: 0.05, y: 40)]))
        #expect(r.touchFrame(frame([touch(x: 0.05, y: 50)])) == [])
    }

    @Test func updateConfigEndsGestureOnRemovedSide() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)]))
        #expect(r.update(config: config(sides: [.left: .brightness])) == [.gestureEnded])
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 60)])) == [])
    }

    @Test func updateConfigKeepsGestureOnSameSide() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)]))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)]))
        #expect(r.update(config: config(step: 2.0)) == [])
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 48)])) == [.steps(function: .volume, count: 2)])
    }
}
