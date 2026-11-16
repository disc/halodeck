import Foundation
import Testing
@testable import HalodeckCore

@Suite struct LevelTrackerTests {
    let step = LevelStep.normal

    @Test func silentAtTop() {
        var t = LevelTracker()
        #expect(t.ticks(for: 3, step: step, function: .volume, now: 0) { 1.0 } == 0)
    }

    @Test func silentAtBottom() {
        var t = LevelTracker()
        #expect(t.ticks(for: -2, step: step, function: .volume, now: 0) { 0.0 } == 0)
    }

    @Test func partialNearTop() {
        var t = LevelTracker()
        #expect(t.ticks(for: 4, step: step, function: .volume, now: 0) { 0.875 } == 2)
    }

    @Test func usesPredictionWhenFresh() {
        var t = LevelTracker()
        #expect(t.ticks(for: 1, step: step, function: .volume, now: 0) { 0.875 } == 1)
        #expect(t.ticks(for: 2, step: step, function: .volume, now: 0.1) { 0.0 } == 1)
    }

    @Test func rereadsWhenStale() {
        var t = LevelTracker()
        #expect(t.ticks(for: 1, step: step, function: .volume, now: 0) { 0.875 } == 1)
        #expect(t.ticks(for: 2, step: step, function: .volume, now: 0.5) { 0.0 } == 2)
    }

    @Test func predictionIsPerFunction() {
        var t = LevelTracker()
        #expect(t.ticks(for: 1, step: step, function: .volume, now: 0) { 1.0 } == 0)
        #expect(t.ticks(for: 1, step: step, function: .brightness, now: 0.1) { 0.5 } == 1)
    }

    @Test func unknownLevelTicksAll() {
        var t = LevelTracker()
        #expect(t.ticks(for: 3, step: step, function: .volume, now: 0) { nil } == 3)
    }

    @Test func tickLevelsReportLevelAfterEachTickingStep() {
        var t = LevelTracker()
        let levels = t.tickLevels(for: 3, step: step, function: .volume, now: 0) { 0.875 }
        #expect(levels == [0.9375, 1.0])
    }

    @Test func tickLevelsUnknownLevel() {
        var t = LevelTracker()
        #expect(t.tickLevels(for: 2, step: step, function: .volume, now: 0) { nil } == [nil, nil])
    }

    @Test func coarseStepsSnapToEighthsAndStopAtTheTop() {
        var t = LevelTracker()
        #expect(t.tickLevels(for: 2, step: .coarse, function: .volume, now: 0) { 0.62 } == [0.75, 0.875])
        #expect(t.tickLevels(for: 2, step: .coarse, function: .volume, now: 0.1) { 0.0 } == [1.0])
    }

    @Test func startIsThePredictedLevelBeforeTheSteps() {
        var t = LevelTracker()
        let first = t.steps(for: 1, step: .normal, function: .volume, now: 0) { 0.5 }
        #expect(first.start == 0.5)
        let second = t.steps(for: 1, step: .normal, function: .volume, now: 0.1) { 0.0 }
        #expect(second.start == 0.5625)
        #expect(second.tickLevels == [0.625])
    }
}

extension LevelTracker {
    mutating func ticks(for steps: Int, step: LevelStep, function: SideAction,
                        now: TimeInterval, read: () -> Double?) -> Int {
        tickLevels(for: steps, step: step, function: function, now: now, read: read).count
    }

    mutating func tickLevels(for steps: Int, step: LevelStep, function: SideAction,
                             now: TimeInterval, read: () -> Double?) -> [Double?] {
        self.steps(for: steps, step: step, function: function, now: now, read: read).tickLevels
    }
}
