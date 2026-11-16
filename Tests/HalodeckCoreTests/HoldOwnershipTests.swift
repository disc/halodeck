import Testing
@testable import HalodeckCore

/// A click held in a side or corner zone stays Halodeck's: it is never handed to the app on a timer
/// (that turned slow slides into text selections), and a corner click never reaches the app at all.
@Suite struct HoldOwnershipTests {
    func resting(x: Double, y: Double = 40, _ cfg: RecognizerConfig = config()) -> Recognizer {
        var r = Recognizer(config: cfg)
        _ = r.touchFrame(frame([touch(x: x, y: y)]))
        return r
    }

    @Test func slowStartInSideStillBecomesGesture() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.tick(time: 1.0) == [])
        #expect(r.isHolding)
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 45)], t: 1.1)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
    }

    @Test func longPressInSideWithoutMovingReplaysClick() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.tick(time: 1.0) == [])
        #expect(r.mouseUp() == (swallow: true, outputs: [.replayHeldClick]))
    }

    @Test func longPressInCornerRunsAction() {
        var r = resting(x: 0.05, y: 80)
        #expect(r.mouseDown() == .hold)
        #expect(r.tick(time: 1.0) == [])
        #expect(r.mouseUp() == (swallow: true, outputs: [.cornerAction(.topLeft)]))
    }

    @Test func cornerClickThatWandersOffIsSwallowed() {
        var r = resting(x: 0.05, y: 80)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: shifted(0.05, byMM: 4), y: 80)], t: 0.1)) == [])
        #expect(r.isHolding)
        #expect(r.mouseDragged() == true)
        #expect(r.mouseUp() == (swallow: true, outputs: []))
    }

    @Test func wanderedCornerClickCannotStartGesture() {
        var r = resting(x: 0.05, y: 80)
        #expect(r.mouseDown() == .hold)
        _ = r.touchFrame(frame([touch(x: shifted(0.05, byMM: 4), y: 80)], t: 0.1))
        #expect(r.touchFrame(frame([touch(x: shifted(0.05, byMM: 4), y: 70)], t: 0.2)) == [])
        #expect(!r.isGestureActive)
    }

    @Test func secondFingerDuringCornerClickKeepsAction() {
        var r = resting(x: 0.05, y: 80)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(1, x: 0.05, y: 80), touch(2, x: 0.5, y: 10)], t: 0.05)) == [])
        #expect(r.mouseUp() == (swallow: true, outputs: [.cornerAction(.topLeft)]))
    }
}
