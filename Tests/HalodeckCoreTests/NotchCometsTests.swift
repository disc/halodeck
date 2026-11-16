import Foundation
import Testing
@testable import HalodeckCore

/// The comet of the Level gauge light on sides without a level: steps that come while it is young
/// feed it (longer tail, thicker line) instead of starting new streaks.
@Suite struct NotchCometsTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func aStepStartsACometThatRunsItsFullTime() {
        var c = NotchComets()
        c.add(at: t0, direction: 1)
        let live = c.live(at: at(0.25))
        #expect(live.count == 1)
        #expect(abs(live[0].progress - 0.5) < 1e-9)
        #expect(live[0].direction == 1)
        #expect(c.live(at: at(0.49)).count == 1)
        #expect(c.live(at: at(0.51)).isEmpty)
    }

    func comet(fed n: Int, direction: Int = 1) -> NotchComets.Live? {
        var c = NotchComets()
        c.add(at: t0, direction: direction)
        for i in 0..<n { c.add(at: at(Double(i + 1) * 0.001), direction: direction) }
        let live = c.live(at: at(0.05))
        return live.count == 1 ? live[0] : nil
    }

    @Test func aFreshCometHasTheShortestTailAndThinnestLine() throws {
        let fresh = try #require(comet(fed: 0, direction: -1))
        #expect(fresh.direction == -1)
        for n in 1...20 {
            let fed = try #require(comet(fed: n, direction: -1))
            #expect(fed.tail > fresh.tail && fed.lineWidth > fresh.lineWidth, "fed \(n)")
        }
    }

    @Test func stepsInTheFirst60PercentFeedTheComet() throws {
        var c = NotchComets()
        c.add(at: t0, direction: 1)
        c.add(at: at(0.1), direction: 1)
        c.add(at: at(0.29), direction: 1)
        let live = c.live(at: at(0.3))
        #expect(live.count == 1)
        let fresh = try #require(comet(fed: 0))
        #expect(live[0].tail > fresh.tail)
        #expect(live[0].lineWidth > fresh.lineWidth)
    }

    @Test func feedingGrowsTheTailAndLineUpToACap() throws {
        let comets = try (0...30).map { try #require(comet(fed: $0)) }
        for (a, b) in zip(comets, comets.dropFirst()) {
            #expect(b.tail >= a.tail && b.lineWidth >= a.lineWidth)
        }
        #expect(comets[2].tail > comets[1].tail && comets[2].lineWidth > comets[1].lineWidth)
        #expect(comets[20].tail == comets[30].tail)
        #expect(comets[20].lineWidth == comets[30].lineWidth)
    }

    @Test func aStepAfterTheWindowStartsANewComet() {
        var c = NotchComets()
        c.add(at: t0, direction: 1)
        c.add(at: at(0.31), direction: 1)
        let live = c.live(at: at(0.4))
        #expect(live.count == 2)
        #expect(live[1].tail == comet(fed: 0)?.tail)
    }

    @Test func reversingStartsANewCometAndTheOldOneFinishes() {
        var c = NotchComets()
        c.add(at: t0, direction: 1)
        c.add(at: at(0.1), direction: -1)
        let live = c.live(at: at(0.2))
        #expect(live.map(\.direction) == [1, -1])
    }

    @Test func atMostTwoRunAtOnce() {
        var c = NotchComets()
        c.add(at: t0, direction: 1)
        c.add(at: at(0.05), direction: -1)
        c.add(at: at(0.1), direction: 1)
        let live = c.live(at: at(0.15))
        #expect(live.map(\.direction) == [-1, 1])
    }
}

@Suite struct NotchGlideTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func startsWhereItIsTold() {
        var g = NotchGlide()
        g.jump(to: 0.4)
        #expect(g.value(at: t0) == 0.4)
    }

    @Test func glidesToTheNewLevelEasingOut() {
        var g = NotchGlide()
        g.jump(to: 0.2)
        g.move(to: 0.8, at: t0)
        #expect(g.value(at: t0) == 0.2)
        let half = g.value(at: at(NotchGlide.duration / 2))
        #expect(half > 0.5 && half < 0.8)
        #expect(g.value(at: at(NotchGlide.duration)) == 0.8)
        #expect(g.value(at: at(5)) == 0.8)
    }

    @Test func aNewTargetMidGlideStartsFromWhereTheLineIs() {
        var g = NotchGlide()
        g.jump(to: 0)
        g.move(to: 1, at: t0)
        let mid = g.value(at: at(0.09))
        g.move(to: 0.5, at: at(0.09))
        #expect(abs(g.value(at: at(0.09)) - mid) < 1e-9)
        #expect(g.value(at: at(1)) == 0.5)
    }
}
