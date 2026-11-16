import Testing
@testable import HalodeckCore

@Suite struct SpeakerSymbolTests {
    @Test func mutedOrSilentShowsTheCrossedSpeaker() {
        #expect(SpeakerSymbol.name(level: 0.6, muted: true) == "speaker.slash.fill")
        #expect(SpeakerSymbol.name(level: 0, muted: false) == "speaker.slash.fill")
    }

    @Test func wavesGrowWithTheLevel() {
        #expect(SpeakerSymbol.name(level: 0.1, muted: false) == "speaker.wave.1.fill")
        #expect(SpeakerSymbol.name(level: 0.5, muted: false) == "speaker.wave.2.fill")
        #expect(SpeakerSymbol.name(level: 0.9, muted: false) == "speaker.wave.3.fill")
    }

    @Test func mutedOrAtZeroIsSilent() {
        #expect(SpeakerSymbol.isSilent(level: 0.6, muted: true))
        #expect(SpeakerSymbol.isSilent(level: 0, muted: false))
        #expect(!SpeakerSymbol.isSilent(level: 1.0 / 64, muted: false))
    }

    /// An output without a volume control or a mute switch is silent only when what it has says so.
    @Test func aMissingControlDoesNotSilence() {
        #expect(!SpeakerSymbol.isSilent(level: nil, muted: false))
        #expect(!SpeakerSymbol.isSilent(level: nil, muted: nil))
        #expect(!SpeakerSymbol.isSilent(level: 0.5, muted: nil))
        #expect(SpeakerSymbol.isSilent(level: nil, muted: true))
        #expect(SpeakerSymbol.isSilent(level: 0, muted: nil))
    }
}
