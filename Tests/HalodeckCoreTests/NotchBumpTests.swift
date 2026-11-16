import Foundation
import Testing
@testable import HalodeckCore

@Suite struct NotchBumpTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 2000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func samples(_ value: (Date) -> Double) -> [(time: Double, value: Double)] {
        stride(from: -0.05, through: 0.8, by: 0.001).map { ($0, value(at($0))) }
    }

    @Test func hittingTheTopPushesTheRightSideAndTheBottomTheLeft() {
        #expect(NotchBump(at: t0, top: true).right)
        #expect(!NotchBump(at: t0, top: false).right)
    }

    @Test func thePushStartsAtRestPeaksEarlyAtAboutSixPointsAndSettles() {
        let bump = NotchBump(at: t0, top: true)
        #expect(bump.push(at: at(-0.01)) == 0)
        #expect(bump.push(at: t0) == 0)
        let s = samples { bump.push(at: $0) }
        let peak = s.max { $0.value < $1.value }!
        #expect(abs(peak.value - 6) < 0.05)
        #expect(peak.time > 0.08 && peak.time < 0.2)
        // It overshoots a little past rest, then comes back to rest.
        let low = s.filter { $0.time > peak.time }.min { $0.value < $1.value }!
        #expect(low.value < -0.3 && low.value >= -0.5 - 1e-9)
        #expect(low.time < NotchBump.pushDuration)
        #expect(abs(bump.push(at: at(NotchBump.pushDuration - 0.001))) < 0.01)
        #expect(bump.push(at: at(NotchBump.pushDuration + 1e-6)) == 0)
        #expect(bump.push(at: at(1)) == 0)
    }

    @Test func thePushMovesSmoothly() {
        let bump = NotchBump(at: t0, top: false)
        let s = samples { bump.push(at: $0) }
        for (a, b) in zip(s, s.dropFirst()) { #expect(abs(b.value - a.value) < 0.15) }
    }

    @Test func reduceMotionHasNoPush() {
        let bump = NotchBump(at: t0, top: true)
        #expect(samples { bump.push(at: $0, reduceMotion: true) }.allSatisfy { $0.value == 0 })
    }

    @Test func theLightComesUpQuicklyAndFadesToNothing() {
        let bump = NotchBump(at: t0, top: true)
        #expect(bump.light(at: at(-0.01)) == 0)
        #expect(bump.light(at: t0) == 0)
        let s = samples { bump.light(at: $0) }
        let peak = s.max { $0.value < $1.value }!
        #expect(abs(peak.value - 1) < 1e-6)
        #expect(abs(peak.time - 0.15 * NotchBump.lightDuration) < 0.005)
        let after = s.filter { $0.time >= peak.time && $0.time <= NotchBump.lightDuration }
        for (a, b) in zip(after, after.dropFirst()) { #expect(b.value <= a.value) }
        #expect(bump.light(at: at(NotchBump.lightDuration + 1e-6)) == 0)
        #expect(bump.light(at: at(2)) == 0)
    }

    /// At 0% the gauge line is empty: the bump there is the push alone, with no light.
    @Test func theBumpAtZeroHasNoLight() {
        let bump = NotchBump(at: t0, top: false)
        #expect(samples { bump.light(at: $0) }.allSatisfy { $0.value == 0 })
        #expect(samples { bump.push(at: $0) }.contains { $0.value > 0 })
    }

    @Test func itIsOverOnceBothThePushAndTheLightHaveFinished() {
        let bump = NotchBump(at: t0, top: true)
        #expect(!bump.isOver(at: at(0.5)))
        #expect(bump.isOver(at: at(max(NotchBump.pushDuration, NotchBump.lightDuration) + 1e-6)))
    }

    @Test func theBumpAtZeroIsOverOnceThePushIs() {
        let bump = NotchBump(at: t0, top: false)
        #expect(!bump.isOver(at: at(NotchBump.pushDuration - 0.01)))
        #expect(bump.isOver(at: at(NotchBump.pushDuration + 1e-6)))
    }
}
