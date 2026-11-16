import Foundation
import Testing
@testable import HalodeckCore

@Suite struct NotchStreaksTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func aStepStartsAStreakThatRunsItsFullTime() {
        var s = NotchStreaks(duration: 0.4)
        s.add(at: t0, direction: 1)
        let early = s.live(at: t0.addingTimeInterval(0.1))
        #expect(early.count == 1 && abs(early[0].progress - 0.25) < 1e-9)
        #expect(s.live(at: t0.addingTimeInterval(0.39)).count == 1)
        #expect(s.live(at: t0.addingTimeInterval(0.41)).isEmpty)
    }

    @Test func aNewStepDoesNotCutThePreviousOneShort() {
        var s = NotchStreaks(duration: 0.4)
        s.add(at: t0, direction: 1)
        s.add(at: t0.addingTimeInterval(0.1), direction: -1)
        let live = s.live(at: t0.addingTimeInterval(0.2))
        #expect(live.count == 2)
        #expect(live.map(\.direction) == [1, -1])
        #expect(abs(live[0].progress - 0.5) < 1e-9)
        #expect(abs(live[1].progress - 0.25) < 1e-9)
    }

    @Test func finishedStreaksAreDropped() {
        var s = NotchStreaks(duration: 0.4)
        s.add(at: t0, direction: 1)
        s.add(at: t0.addingTimeInterval(1), direction: 1)
        #expect(s.count == 1)
    }

    @Test func aFastSlideKeepsAtMostTheNewestFew() {
        var s = NotchStreaks(duration: 0.4, limit: 6)
        for i in 0..<20 { s.add(at: t0.addingTimeInterval(Double(i) * 0.01), direction: 1) }
        #expect(s.count == 6)
        #expect(s.live(at: t0.addingTimeInterval(0.2)).count == 6)
    }
}
