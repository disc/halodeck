import Testing
@testable import HalodeckCore

@Suite struct DeviceLossTests {
    @Test func gestureEndsWhenDeviceGoesSilent() {
        var r = resting(x: 0.95)
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)], t: 0.0))
        #expect(r.isGestureActive)
        #expect(r.tick(time: 0.2) == [])
        #expect(r.tick(time: 0.3) == [.gestureEnded])
        #expect(!r.isGestureActive)
    }

    @Test func forgetDevicesEndsGestureAndDropsGhosts() {
        var r = resting(x: 0.95)
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)]))
        #expect(r.forgetDevices(notIn: [2]) == [.gestureEnded])
        // The ghost finger on device 1 no longer blocks clicks on device 2.
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)], device: 2))
        #expect(r.mouseDown() == .hold)
    }

    @Test func forgetDevicesReleasesHold() {
        var r = resting(x: 0.95)
        #expect(r.mouseDown() == .hold)
        #expect(r.forgetDevices(notIn: []) == [.releaseHeldDown])
        #expect(!r.isHolding)
    }

    @Test func forgetKnownDeviceKeepsGesture() {
        var r = resting(x: 0.95)
        _ = r.touchFrame(frame([touch(x: 0.95, y: 44)]))
        #expect(r.forgetDevices(notIn: [1]) == [])
        #expect(r.isGestureActive)
    }
}

@Suite struct TwoTrackpadHoldTests {
    @Test func noSwipeOnAnotherTrackpadWhileAClickIsHeld() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)], device: 1))
        #expect(r.mouseDown() == .hold)
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)], t: 0.05, device: 2))
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 50)], t: 0.1, device: 2)) == [])
        #expect(!r.isGestureActive)
        #expect(r.isHolding)
        #expect(r.touchFrame(frame([touch(x: 0.95, y: 46)], t: 0.15, device: 1)) ==
                [.gestureBegan(side: .right, function: .volume, device: 1, finger: 1)])
        #expect(r.mouseUp() == (swallow: true, outputs: []))
    }

    @Test func heldClickOnAnotherTrackpadStillReplaysAsAClick() {
        var r = Recognizer(config: config())
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)], device: 1))
        #expect(r.mouseDown() == .hold)
        _ = r.touchFrame(frame([touch(x: 0.95, y: 40)], t: 0.05, device: 2))
        _ = r.touchFrame(frame([touch(x: 0.95, y: 50)], t: 0.1, device: 2))
        #expect(r.mouseUp() == (swallow: true, outputs: [.replayHeldClick]))
        #expect(!r.isGestureActive)
    }
}
