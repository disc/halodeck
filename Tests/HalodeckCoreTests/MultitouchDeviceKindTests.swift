import Testing
@testable import HalodeckCore

@Suite struct MultitouchDeviceKindTests {
    @Test func builtInTrackpadIsTrackpad() {
        // This Mac's real I/O registry values.
        let info = MultitouchDeviceInfo(
            product: "Apple Internal Keyboard / Trackpad",
            usagePairs: [HIDUsagePair(page: 1, usage: 2), HIDUsagePair(page: 1, usage: 1),
                         HIDUsagePair(page: 13, usage: 5), HIDUsagePair(page: 65280, usage: 12)])
        #expect(info.kind == .trackpad)
    }

    @Test func magicMouseIsMouse() {
        let info = MultitouchDeviceInfo(product: "Magic Mouse", usagePairs: [HIDUsagePair(page: 1, usage: 2)])
        #expect(info.kind == .mouse)
    }

    @Test func mouseNameWithoutUsagePairsIsMouse() {
        let info = MultitouchDeviceInfo(product: "Some magic MOUSE", usagePairs: [])
        #expect(info.kind == .mouse)
    }

    @Test func genericMousePairWithoutNameIsMouse() {
        let info = MultitouchDeviceInfo(product: nil, usagePairs: [HIDUsagePair(page: 1, usage: 2)])
        #expect(info.kind == .mouse)
    }

    @Test func magicTrackpadIsTrackpad() {
        let info = MultitouchDeviceInfo(product: "Magic Trackpad", usagePairs: [HIDUsagePair(page: 13, usage: 5)])
        #expect(info.kind == .trackpad)
    }

    @Test func noPropertiesIsTrackpad() {
        #expect(MultitouchDeviceInfo(product: nil, usagePairs: nil).kind == .trackpad)
    }

    @Test func unreadableUsagePairsIsTrackpad() {
        // Without the pairs we can't rule out a touch pad, so keep the device.
        #expect(MultitouchDeviceInfo(product: "Magic Mouse", usagePairs: nil).kind == .trackpad)
    }

    @Test func mouseNameWithTouchPadPairIsTrackpad() {
        let info = MultitouchDeviceInfo(product: "Mouse-shaped Trackpad",
                                        usagePairs: [HIDUsagePair(page: 1, usage: 2), HIDUsagePair(page: 13, usage: 5)])
        #expect(info.kind == .trackpad)
    }
}
