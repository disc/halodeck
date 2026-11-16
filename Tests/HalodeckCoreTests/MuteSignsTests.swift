import Foundation
import Testing
@testable import HalodeckCore

/// Which muted signs sit on which side of the notch, in screen order (left to right) within each ear.
@Suite struct MuteSignsLayoutTests {
    @Test func nothingMutedShowsNothing() {
        for side in MuteSignsSide.allCases {
            let layout = side.layout(sound: false, microphone: false)
            #expect(layout.left.isEmpty && layout.right.isEmpty)
            #expect(layout.isEmpty)
        }
    }

    @Test func rightPutsBothRightWithTheMicrophoneOutermost() {
        #expect(MuteSignsSide.right.layout(sound: true, microphone: false) == MuteSignsLayout(left: [], right: [.sound]))
        #expect(MuteSignsSide.right.layout(sound: false, microphone: true) == MuteSignsLayout(left: [], right: [.microphone]))
        #expect(MuteSignsSide.right.layout(sound: true, microphone: true) == MuteSignsLayout(left: [], right: [.sound, .microphone]))
    }

    @Test func leftMirrorsRightWithTheMicrophoneOutermost() {
        #expect(MuteSignsSide.left.layout(sound: true, microphone: false) == MuteSignsLayout(left: [.sound], right: []))
        #expect(MuteSignsSide.left.layout(sound: false, microphone: true) == MuteSignsLayout(left: [.microphone], right: []))
        #expect(MuteSignsSide.left.layout(sound: true, microphone: true) == MuteSignsLayout(left: [.microphone, .sound], right: []))
    }
}
