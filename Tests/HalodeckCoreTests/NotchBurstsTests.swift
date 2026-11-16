import Foundation
import Testing
@testable import HalodeckCore

@Suite struct NotchBurstsTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 500)

    @Test func oneClickOneBurstFromItsSide() {
        var b = NotchBursts(duration: 0.5, spacing: 0.15)
        b.add(left: true, top: true, clicks: 1, at: t0)
        let live = b.live(at: t0.addingTimeInterval(0.1))
        #expect(live.count == 1)
        #expect(live[0].left)
        #expect(live[0].top)
        #expect(abs(live[0].progress - 0.2) < 1e-9)
        #expect(b.live(at: t0.addingTimeInterval(0.51)).isEmpty)
    }

    @Test func doubleClickSendsASecondBurstJustAfter() {
        var b = NotchBursts(duration: 0.5, spacing: 0.15)
        b.add(left: false, top: false, clicks: 2, at: t0)
        #expect(b.live(at: t0.addingTimeInterval(0.1)).count == 1)   // the second hasn't started
        let both = b.live(at: t0.addingTimeInterval(0.2))
        #expect(both.count == 2)
        #expect(both.allSatisfy { !$0.left && !$0.top })
        #expect(b.live(at: t0.addingTimeInterval(0.6)).count == 1)   // the second outlives the first
    }

    @Test func finishedBurstsAreDropped() {
        var b = NotchBursts(duration: 0.5, spacing: 0.15)
        b.add(left: true, top: true, clicks: 2, at: t0)
        b.add(left: true, top: false, clicks: 1, at: t0.addingTimeInterval(2))
        #expect(b.count == 1)
    }
}
