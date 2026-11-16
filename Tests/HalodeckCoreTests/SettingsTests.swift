import Foundation
import Testing
@testable import HalodeckCore

@Suite struct SettingsTests {
    @Test func defaultsMatchSpec() {
        let s = HalodeckSettings()
        #expect(s.enabled)
        #expect(s.sides == [.left: .brightness, .right: .volume, .top: .mediaSeek, .bottom: .customKeys])
        #expect(s.corners == [.topLeft: .muteMicrophone, .topRight: .mute, .bottomLeft: .openApp(path: ""), .bottomRight: .keyCombo(.unset)])
        #expect(s.multiClickCorners.isEmpty)
        #expect(s.customKeys.isEmpty)
        #expect(s.swipeWithoutClick == [.left: false, .right: false, .top: false, .bottom: false])
        // Ticks for the level sides; top and bottom have no level to tick against.
        #expect(s.ticksEnabled == [.left: true, .right: true, .top: false, .bottom: false])
        #expect(s.hapticStrength == .soft)
        #expect(s.soundChoice == nil)
        #expect(s.soundStyle == .softClick)
        #expect(s.sideWidthFraction == 0.10)
        #expect(s.slidePerStepMM == 4.0)
        #expect(s.fineControlKey == .option)
        #expect(s.coarseControlKey == .shift)
        #expect(s.menuBarClick == .toggle)
        #expect(s.brightnessDirect == false)
        #expect(s.showIndicator)
        #expect(s.showInNotch)
        #expect(s.notchEffect == .levelGauge)
        #expect(s.muteSignsSide == .right)
    }

    /// Settings saved before a property existed load with that property's default.
    @Test func emptySavedSettingsLoadAsTheDefaults() throws {
        let s = try JSONDecoder().decode(HalodeckSettings.self, from: Data("{}".utf8)).sanitized()
        #expect(s == HalodeckSettings())
    }

    @Test func sanitizedClamps() {
        var s = HalodeckSettings()
        s.sideWidthFraction = 0.5
        s.slidePerStepMM = 1
        s.hapticTick = 7
        s.sides = [.right: .volume]
        let clean = s.sanitized()
        #expect(clean.sideWidthFraction == 0.20)
        #expect(clean.slidePerStepMM == 2.0)
        #expect(clean.hapticTick == 1)
        #expect(clean.sides[.left] == .brightness)
        #expect(clean.sides[.right] == .volume)
    }

    @MainActor @Test func storeRoundTripMakesNoBackup() throws {
        let suite = "halodeck.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.settings.corners[.topRight] = .openLink(url: "https://example.com")

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.corners[.topRight] == .openLink(url: "https://example.com"))
        #expect(reloaded.settings == store.settings)
        #expect(defaults.object(forKey: SettingsStore.unreadableKey) == nil)
    }

    @MainActor @Test func unreadableDataFallsBackToDefaultsAndIsKept() throws {
        let suite = "halodeck.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let unreadable = Data("x".utf8)
        defaults.set(unreadable, forKey: SettingsStore.key)
        let store = SettingsStore(defaults: defaults)
        #expect(store.settings == HalodeckSettings())
        #expect(defaults.data(forKey: SettingsStore.unreadableKey) == unreadable)

        store.settings.soundEnabled = true   // saves over the main key
        #expect(defaults.data(forKey: SettingsStore.unreadableKey) == unreadable)
        #expect(SettingsStore(defaults: defaults).settings.soundEnabled)
    }

    @MainActor @Test func unreadableNonDataValueIsKept() throws {
        let suite = "halodeck.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("not json", forKey: SettingsStore.key)
        #expect(SettingsStore(defaults: defaults).settings == HalodeckSettings())
        #expect(defaults.string(forKey: SettingsStore.unreadableKey) == "not json")
    }
}
