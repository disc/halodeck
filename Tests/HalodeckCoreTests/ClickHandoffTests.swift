import Testing
@testable import HalodeckCore

/// Once a click has been let through to the app, a swipe must not take it over.
@Suite struct ClickHandoffTests {
    @Test func diagonalDragStaysAClick() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: shifted(0.95, byMM: -2), y: 37)], t: 0.1)) == [.releaseHeldDown])
        #expect(r.touchFrame(frame([touch(x: shifted(0.95, byMM: -2), y: 30)], t: 0.2)) == [])
        #expect(r.mouseUp() == (swallow: false, outputs: []))
    }

    @Test func passedClickThenVerticalDragStaysAClick() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.91, y: 40)]))
        _ = r.touchFrame(frame([touch(x: shifted(0.91, byMM: -2), y: 40)]))   // just outside the strip
        #expect(r.mouseDown() == .pass)
        #expect(r.touchFrame(frame([touch(x: shifted(0.91, byMM: -2), y: 50)], t: 0.1)) == [])
        #expect(r.mouseUp() == (swallow: false, outputs: []))
    }

    @Test func swipeWorksAgainAfterTheClickEnds() {
        var r = resting(x: 0.5)
        #expect(r.mouseDown() == .pass)
        _ = r.mouseUp()
        _ = r.touchFrame(frame([], t: 0.2))
        _ = r.touchFrame(frame([touch(2, x: 0.95, y: 40)], t: 0.3))
        #expect(r.touchFrame(frame([touch(2, x: 0.95, y: 44)], t: 0.35)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 2)])
    }
}

@Suite struct CornerDeactivatedDuringHoldTests {
    @Test func cornerSwitchedOffWhileHeldReplaysTheClick() {
        var r = Recognizer(config: config(corners: [.topLeft]))
        _ = r.touchFrame(frame([touch(x: 0.05, y: 80)]))
        #expect(r.mouseDown() == .hold)
        _ = r.update(config: config(corners: []))
        #expect(r.mouseUp() == (swallow: true, outputs: [.replayHeldClick]))
    }
}
