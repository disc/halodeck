import Testing
@testable import HalodeckCore

@Suite struct RecognizerClickTests {
    @Test func plainClickInStripReplays() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        let up = r.mouseUp()
        #expect(up.swallow == true)
        #expect(up.outputs == [.replayHeldClick])
        #expect(!r.isHolding)
    }

    @Test func doubleClickInStripReplaysBoth() {
        var r = resting(x: 0.95)
        var all: [RecognizerOutput] = []
        for t in [0.0, 0.15] {
            #expect(r.mouseDown() == .hold)
            all += r.touchFrame(frame([touch(x: 0.95, y: 40.2)], t: t + 0.05))
            let up = r.mouseUp()
            #expect(up.swallow)
            all += up.outputs
        }
        #expect(all == [.replayHeldClick, .replayHeldClick])
    }

    @Test func clickThenVerticalSlideBecomesGesture() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 45)], t: 0.1)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
        #expect(!r.isHolding)
        #expect(r.mouseDragged() == true)
        let up = r.mouseUp()
        #expect(up.swallow == true)
        #expect(up.outputs == [])
    }

    @Test func clickAndSlideModeStartsGestureFromHold() {
        var r = resting(x: 0.95, config(swipe: false))
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 45)], t: 0.1)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
    }

    @Test func dragSelectSidewaysReleases() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(x: shifted(0.95, byMM: -4), y: 40)], t: 0.1)) == [.releaseHeldDown])
        #expect(r.mouseDragged() == false)
        let up = r.mouseUp()
        #expect(up.swallow == false)
        #expect(up.outputs == [])
    }

    @Test func clickOutsideStripPasses() {
        var r = resting(x: 0.5)
        #expect(r.mouseDown() == .pass)
        #expect(r.mouseUp() == (swallow: false, outputs: []))
    }

    static func point(_ corner: Corner) -> (x: Double, y: Double) {
        (corner.isLeft ? 0.05 : 0.95, corner.isTop ? 80 : 5)
    }

    @Test(arguments: Corner.allCases, [true, false])
    func cornerClickRunsAction(_ corner: Corner, swipe: Bool) {
        let p = Self.point(corner)
        var r = resting(x: p.x, y: p.y, config(swipe: swipe, corners: [corner]))
        #expect(r.mouseDown() == .hold)
        #expect(r.mouseUp() == (swallow: true, outputs: [.cornerAction(corner)]))
    }

    @Test(arguments: Corner.allCases)
    func cornerWithoutActionIsAPlainClick(_ corner: Corner) {
        let p = Self.point(corner)
        var r = resting(x: p.x, y: p.y, config(corners: []))
        #expect(r.mouseDown() == .hold)   // still in the left or right side strip
        #expect(r.mouseUp().outputs == [.replayHeldClick])
    }

    @Test func inactiveZoneClickPasses() {
        var r = resting(x: 0.95, config(sides: [:], corners: []))
        #expect(r.mouseDown() == .pass)
    }

    @Test func downDuringGestureSwallowed() {
        var r = resting(x: 0.95)
        _ = r.touchFrame(frame([touch(x: 0.95, y: 45)]))
        #expect(r.isGestureActive)
        #expect(r.mouseDown() == .swallow)
        #expect(r.mouseUp().swallow)
    }

    @Test func secondFingerWhileHoldingReleases() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.touchFrame(frame([touch(1, x: 0.95, y: 40), touch(2, x: 0.6, y: 30)], t: 0.05)) == [.releaseHeldDown])
    }
}
