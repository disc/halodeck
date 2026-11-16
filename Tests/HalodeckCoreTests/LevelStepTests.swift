import Testing
@testable import HalodeckCore

@Suite struct LevelStepTests {
    @Test func normalAndFineStepsAddTheirSizeAndClamp() {
        #expect(LevelStep.normal.level(from: 0.5, steps: 2) == 0.5 + 2.0 / 16)
        #expect(LevelStep.fine.level(from: 0.5, steps: -3) == 0.5 - 3.0 / 64)
        #expect(LevelStep.normal.level(from: 0.97, steps: 1) == 1)
        #expect(LevelStep.fine.level(from: 0.01, steps: -1) == 0)
    }

    @Test func coarseSnapsUpAndDownFromBetweenEighths() {
        #expect(LevelStep.coarse.level(from: 0.55, steps: 1) == 0.625)
        #expect(LevelStep.coarse.level(from: 0.55, steps: -1) == 0.5)
        #expect(LevelStep.coarse.level(from: 0.3, steps: 1) == 0.375)
        #expect(LevelStep.coarse.level(from: 0.3, steps: -1) == 0.25)
    }

    @Test func coarseFromExactlyAnEighthMovesAWholeEighth() {
        #expect(LevelStep.coarse.level(from: 0.5, steps: 1) == 0.625)
        #expect(LevelStep.coarse.level(from: 0.5, steps: -1) == 0.375)
        #expect(LevelStep.coarse.level(from: 0, steps: 1) == 0.125)
    }

    /// A level within half a fine step of an eighth counts as on it: 62% (shown for 62.5%) goes to
    /// 75% up and 50% down.
    @Test func coarseTreatsALevelJustOffAnEighthAsOnIt() {
        #expect(LevelStep.coarse.level(from: 0.62, steps: 1) == 0.75)
        #expect(LevelStep.coarse.level(from: 0.62, steps: -1) == 0.5)
        #expect(LevelStep.coarse.level(from: 0.6251, steps: 1) == 0.75)
        // A fine step off an eighth is between eighths.
        #expect(LevelStep.coarse.level(from: 0.625 - 1.0 / 64, steps: 1) == 0.625)
    }

    @Test func coarseClampsAtBothEnds() {
        #expect(LevelStep.coarse.level(from: 1, steps: 1) == 1)
        #expect(LevelStep.coarse.level(from: 0.95, steps: 3) == 1)
        #expect(LevelStep.coarse.level(from: 0, steps: -1) == 0)
        #expect(LevelStep.coarse.level(from: 0.05, steps: -2) == 0)
    }

    @Test func coarseTakesSeveralStepsAtOnce() {
        #expect(LevelStep.coarse.level(from: 0.55, steps: 3) == 0.875)
        #expect(LevelStep.coarse.level(from: 0.55, steps: -3) == 0.25)
        #expect(LevelStep.coarse.level(from: 0.5, steps: 0) == 0.5)
    }

    /// With media keys (a sixteenth each), a coarse step presses as many as reach the next eighth.
    @Test func keyPressesPerStep() {
        #expect(LevelStep.normal.keyPresses(from: 0.5, up: true) == 1)
        #expect(LevelStep.fine.keyPresses(from: nil, up: false) == 1)
        #expect(LevelStep.coarse.keyPresses(from: 0.5, up: true) == 2)
        #expect(LevelStep.coarse.keyPresses(from: 0.5625, up: true) == 1)
        #expect(LevelStep.coarse.keyPresses(from: 0.5625, up: false) == 1)
        #expect(LevelStep.coarse.keyPresses(from: 1, up: true) == 0)
        #expect(LevelStep.coarse.keyPresses(from: nil, up: true) == 2)
    }

    @Test func modifierRule() {
        #expect(LevelStep.chosen(isLevel: true, fine: false, coarse: false) == .normal)
        #expect(LevelStep.chosen(isLevel: true, fine: true, coarse: false) == .fine)
        #expect(LevelStep.chosen(isLevel: true, fine: false, coarse: true) == .coarse)
        #expect(LevelStep.chosen(isLevel: true, fine: true, coarse: true) == .fine)
        #expect(LevelStep.chosen(isLevel: false, fine: true, coarse: true) == .normal)
    }
}
