import Testing
@testable import HalodeckCore

@Suite struct SoundTests {
    @Test func pitchRunsFromC5AtTheBottomToC7AtTheTop() {
        #expect(abs(SoundPitch.frequency(forLevel: 0) - 523.25) < 0.01)    // C5
        #expect(abs(SoundPitch.frequency(forLevel: 0.5) - 1046.50) < 0.01) // C6
        #expect(abs(SoundPitch.frequency(forLevel: 1) - 2093.00) < 0.01)   // C7
    }

    @Test func pitchRisesWithLevel() {
        let levels = stride(from: 0.0, through: 1.0, by: 1.0 / 16).map { SoundPitch.frequency(forLevel: $0) }
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func unknownLevelUsesMiddleNote() {
        #expect(abs(SoundPitch.frequency(forLevel: nil) - 783.99) < 0.01)  // G5
    }

    @Test func pitchShiftIsZeroAtTheMiddleNote() {
        #expect(abs(SoundPitch.cents(forLevel: 0.5)) < 0.01)
        #expect(abs(SoundPitch.cents(forLevel: 0) - -1200) < 0.5)
        #expect(abs(SoundPitch.cents(forLevel: 1) - 1200) < 0.5)
    }
}
