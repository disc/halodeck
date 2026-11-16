import Testing
@testable import HalodeckCore

@Suite struct TopAndBottomSideTests {
    let all: [Side: SideAction] = [.left: .brightness, .right: .volume, .top: .switchTab, .bottom: .mediaSeek]

    func resting(x: Double, y: Double) -> Recognizer {
        var r = Recognizer(config: config(sides: all))
        _ = r.touchFrame(frame([touch(x: x, y: y)]))
        return r
    }

    @Test func bottomPressAndSlideSeeks() {
        var r = resting(x: 0.5, y: 5)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 4), y: 5)], t: 0.1)) ==
                [.gestureBegan(side: .bottom, function: .mediaSeek, device: 1, finger: 1)])
        // 1.5 × 4 mm = 6 mm per seek step; 13 mm further right = 2 steps.
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 17), y: 5)], t: 0.2)) == [.steps(function: .mediaSeek, count: 2)])
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 4), y: 5)], t: 0.3)) == [.steps(function: .mediaSeek, count: -2)])
    }

    @Test func bottomSwipeWithoutClickDoesNothing() {
        var r = resting(x: 0.5, y: 5)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 10), y: 5)], t: 0.1)) == [])
        #expect(!r.isGestureActive)
    }

    @Test func topPressAndSlideSwitchesTab() {
        var r = resting(x: 0.5, y: 80)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: -4), y: 80)], t: 0.1)) ==
                [.gestureBegan(side: .top, function: .switchTab, device: 1, finger: 1)])
        // 3 × 4 mm = 12 mm per tab.
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: -21), y: 80)], t: 0.2)) == [.steps(function: .switchTab, count: -1)])
    }

    @Test func cornerPressAndSlideSidewaysUsesTopSide() {
        var r = resting(x: 0.05, y: 80)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: shifted(0.05, byMM: 4), y: 80)], t: 0.1)) ==
                [.gestureBegan(side: .top, function: .switchTab, device: 1, finger: 1)])
    }

    @Test func cornerPressAndSlideDownUsesLeftSide() {
        var r = resting(x: 0.05, y: 80)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: 0.05, y: 76)], t: 0.1)) ==
                [.gestureBegan(side: .left, function: .brightness, device: 1, finger: 1)])
    }

    @Test func plainClickInBottomStripReplays() {
        var r = resting(x: 0.5, y: 5)
        #expect(r.mouseDown() == .hold)
        #expect(r.mouseUp() == (swallow: true, outputs: [.replayHeldClick]))
    }

    @Test func verticalDragFromBottomStripPasses() {
        var r = resting(x: 0.5, y: 5)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: 0.5, y: 12)], t: 0.1)) == [.releaseHeldDown])
    }

    @Test func horizontalSidesOffMeansClicksPass() {
        var r = Recognizer(config: config(sides: [.left: .brightness, .right: .volume]))
        _ = r.touchFrame(frame([touch(x: 0.5, y: 5)]))
        #expect(r.mouseDown() == .pass)
    }
}
