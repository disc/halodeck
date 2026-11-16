import Foundation
import Testing
@testable import HalodeckCore

/// Settings → Advanced → Feedback → "Haptic feedback": Off, Soft, Medium or Strong over the stored
/// `hapticsEnabled` and `hapticTick`, so saved settings keep working.
@Suite struct HapticStrengthTests {
    @Test func readsTheStoredSwitchAndTap() {
        var s = HalodeckSettings()
        for (tick, strength) in [(Int32(1), HapticStrength.soft), (4, .medium), (6, .strong)] {
            s.hapticTick = tick
            #expect(s.hapticStrength == strength)
        }
        s.hapticsEnabled = false
        #expect(s.hapticStrength == .off)
    }

    @Test func settingAStrengthStoresSwitchAndTap() {
        var s = HalodeckSettings()
        s.hapticStrength = .strong
        #expect(s.hapticsEnabled && s.hapticTick == 6)
        s.hapticStrength = .medium
        #expect(s.hapticsEnabled && s.hapticTick == 4)
        s.hapticStrength = .off
        #expect(!s.hapticsEnabled)
        s.hapticStrength = .soft
        #expect(s.hapticsEnabled && s.hapticTick == 1)
    }

    @Test(arguments: [Int32(0), 7, -3, 99])
    func anUnknownSavedTapFallsBackToSoft(_ saved: Int32) {
        var s = HalodeckSettings()
        s.hapticTick = saved
        #expect(s.hapticStrength == .soft)
        #expect(s.sanitized().hapticTick == 1)
    }

    @Test(arguments: [Int32(1), 4, 6])
    func theOfferedTapsAreKept(_ saved: Int32) {
        var s = HalodeckSettings()
        s.hapticTick = saved
        #expect(s.sanitized().hapticTick == saved)
    }
}
