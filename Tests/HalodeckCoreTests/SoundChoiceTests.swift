import Foundation
import Testing
@testable import HalodeckCore

/// Settings › Advanced › Sound feedback is one menu: Off or a sound. It reads and writes the two stored
/// keys (`soundEnabled`, `soundStyle`), so saved settings keep loading.
@Suite struct SoundChoiceTests {
    @Test func choosingASoundTurnsSoundOnWithThatSound() {
        var s = HalodeckSettings()
        s.soundChoice = .glass
        #expect(s.soundEnabled && s.soundStyle == .glass)
        #expect(s.soundChoice == .glass)
    }

    @Test func offKeepsTheChosenSoundForNextTime() {
        var s = HalodeckSettings()
        s.soundChoice = .marimba
        s.soundChoice = nil
        #expect(!s.soundEnabled && s.soundStyle == .marimba)
        #expect(s.soundChoice == nil)
    }
}
