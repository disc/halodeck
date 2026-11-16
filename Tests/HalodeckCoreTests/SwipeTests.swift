import Testing
@testable import HalodeckCore

@Suite struct PerSideSwipeTests {
    @Test func onlyChosenSidesStartWithoutAClick() {
        var cfg = config(sides: [.left: .brightness, .right: .volume])
        cfg.swipeSides = [.right]
        var r = Recognizer(config: cfg)
        _ = r.touchFrame(frame([touch(1, x: 0.05, y: 40)]))
        #expect(r.touchFrame(frame([touch(1, x: 0.05, y: 50)], t: 0.1)) == [])
        _ = r.touchFrame(frame([], t: 0.2))
        _ = r.touchFrame(frame([touch(2, x: 0.95, y: 40)], t: 0.3))
        #expect(r.touchFrame(frame([touch(2, x: 0.95, y: 45)], t: 0.4)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 2)])
    }
}

@Suite struct ClicklessHorizontalSwipeTests {
    let all: [Side: SideAction] = [.left: .brightness, .right: .volume, .top: .switchTab, .bottom: .mediaSeek]

    func resting(x: Double, y: Double) -> Recognizer {
        var r = Recognizer(config: config(sides: all, horizontalSwipe: true))
        _ = r.touchFrame(frame([touch(x: x, y: y)]))
        return r
    }

    @Test func swipeAlongTheVeryBottomSeeks() {
        var r = resting(x: 0.5, y: 2)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 4), y: 2.5)], t: 0.1)) ==
                [.gestureBegan(side: .bottom, function: .mediaSeek, device: 1, finger: 1)])
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 11), y: 2.5)], t: 0.2)) == [.steps(function: .mediaSeek, count: 1)])
    }

    @Test func swipeAlongTheVeryTopSwitchesTab() {
        var r = resting(x: 0.5, y: Pad.height - 2)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: -4), y: Pad.height - 2)], t: 0.1)) ==
                [.gestureBegan(side: .top, function: .switchTab, device: 1, finger: 1)])
    }

    @Test func startingHigherInTheStripDoesNothing() {
        var r = resting(x: 0.5, y: 7)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 10), y: 7)], t: 0.1)) == [])
    }

    @Test func diagonalSwipeDoesNothing() {
        var r = resting(x: 0.5, y: 2)
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 4), y: 4)], t: 0.1)) == [])
        #expect(r.touchFrame(frame([touch(x: shifted(0.5, byMM: 15), y: 4)], t: 0.2)) == [])
    }

    @Test func verticalSwipeFromBottomCornerStillUsesRightSide() {
        var r = resting(x: 0.95, y: 2)
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 6)], t: 0.1)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
    }
}
