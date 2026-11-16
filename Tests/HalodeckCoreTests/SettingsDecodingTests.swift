import Foundation
import Testing
@testable import HalodeckCore

private func decode(_ json: String) throws -> HalodeckSettings {
    try JSONDecoder().decode(HalodeckSettings.self, from: Data(json.utf8))
}

/// One unknown or malformed value must cost only that value: every other setting still loads.
/// `soundEnabled: true` (not the default) shows the rest of the settings survived.
@Suite struct LenientSettingsDecodingTests {
    @Test func unknownFineControlKeyFallsBack() throws {
        let s = try decode(#"{"fineControlKey":"hyper","soundEnabled":true}"#)
        #expect(s.fineControlKey == .option)
        #expect(s.soundEnabled)
    }

    @Test func unknownCoarseControlKeyFallsBack() throws {
        let s = try decode(#"{"coarseControlKey":"capsLock","soundEnabled":true}"#)
        #expect(s.coarseControlKey == .shift)
        #expect(s.soundEnabled)
    }

    @Test func unknownMenuBarClickFallsBack() throws {
        let s = try decode(#"{"menuBarClick":"tripleClick","soundEnabled":true}"#)
        #expect(s.menuBarClick == .toggle)
        #expect(s.soundEnabled)
    }

    @Test func unknownSoundStyleAndNotchEffectFallBack() throws {
        let s = try decode(#"{"soundStyle":"gong","notchEffect":"fireworks","soundEnabled":true}"#)
        #expect(s.soundStyle == .softClick)
        #expect(s.notchEffect == .levelGauge)
        #expect(s.soundEnabled)
    }

    @Test func unknownMuteSignsSideFallsBack() throws {
        let s = try decode(#"{"muteSignsSide":"above","soundEnabled":true}"#)
        #expect(s.muteSignsSide == .right)
        #expect(s.soundEnabled)
    }

    @Test func wrongTypedScalarsFallBack() throws {
        let s = try decode(#"{"enabled":"yes","edgeWidthFraction":"wide","hapticTick":"x","hapticsEnabled":1,"soundEnabled":true}"#)
        #expect(s.enabled)
        #expect(s.sideWidthFraction == 0.10)
        #expect(s.hapticTick == 1)
        #expect(s.hapticsEnabled)
        #expect(s.soundEnabled)
    }

    @Test func unknownSideKeysAreDroppedFromSwitches() throws {
        let s = try decode(#"""
        {"ticksEnabled":{"middle":true,"top":true},
         "swipeWithoutClick":{"middle":false,"left":false},
         "soundEnabled":true}
        """#).sanitized()
        #expect(s.ticksEnabled == [.left: true, .right: true, .top: true, .bottom: false])
        #expect(s.swipeWithoutClick == [.left: false, .right: false, .top: false, .bottom: false])
        #expect(s.soundEnabled)
    }

    @Test func malformedSwitchValuesAreDropped() throws {
        let s = try decode(#"{"ticksEnabled":{"left":"off","right":false},"soundEnabled":true}"#).sanitized()
        #expect(s.ticksEnabled == [.left: true, .right: false, .top: false, .bottom: false])
        #expect(s.soundEnabled)
    }

    @Test func unknownSideOrActionFallsBackPerSide() throws {
        let s = try decode(#"{"edges":{"middle":"volume","left":"warpDrive","right":"track"},"soundEnabled":true}"#).sanitized()
        #expect(s.sides == [.left: .brightness, .right: .track, .top: .mediaSeek, .bottom: .customKeys])
        #expect(s.soundEnabled)
    }

    @Test func unknownCornerOrActionFallsBackPerCorner() throws {
        let s = try decode(#"""
        {"corners":{"center":{"mute":{}},"bottomLeft":{"teleport":{}},"topRight":{"showApps":{}}},
         "soundEnabled":true}
        """#).sanitized()
        #expect(s.corners == [.topLeft: .muteMicrophone, .topRight: .showApps,
                              .bottomLeft: .openApp(path: ""), .bottomRight: .keyCombo(.unset)])
        #expect(s.soundEnabled)
    }

    @Test func unknownMultiClickEntriesAreDropped() throws {
        let s = try decode(#"""
        {"multiClickCorners":{"center":{"2":{"mute":{}}},
                              "topLeft":{"2":{"teleport":{}}},
                              "topRight":{"two":{"mute":{}},"2":{"lockScreen":{}}}},
         "soundEnabled":true}
        """#).sanitized()
        #expect(s.multiClickCorners == [.topRight: [2: .lockScreen]])
        #expect(s.soundEnabled)
    }

    @Test func unknownCustomKeysSideIsDropped() throws {
        let s = try decode(#"""
        {"customKeys":{"middle":{"up":{"keyCode":30,"modifiers":0}},
                       "left":{"up":"⌘]"},
                       "top":{"up":{"keyCode":30,"modifiers":1048576}}},
         "soundEnabled":true}
        """#)
        #expect(s.customKeys == [.top: CustomKeys(up: KeyCombo(keyCode: 30, modifiers: KeyCombo.commandFlag))])
        #expect(s.soundEnabled)
    }
}

/// A property added to HalodeckSettings but missed
/// in `init(from:)` would come back as its default and fail here.
@Suite struct SettingsRoundTripTests {
    static func everythingChanged() -> HalodeckSettings {
        var s = HalodeckSettings()
        s.enabled = false
        s.sides = [.left: .customKeys, .right: .track, .top: .keyboardBacklight, .bottom: .nothing]
        s.corners = [.topLeft: .keyCombo(KeyCombo(keyCode: 4, modifiers: KeyCombo.shiftFlag)),
                     .topRight: .openApp(path: "/Applications/Notes.app"),
                     .bottomLeft: .runShortcut(name: "Focus"), .bottomRight: .appExpose]
        s.multiClickCorners = [.topLeft: [2: .showDesktop], .bottomRight: [2: .openLink(url: "https://example.com")]]
        s.swipeWithoutClick = [.left: true, .right: false, .top: true, .bottom: false]
        s.ticksEnabled = [.left: false, .right: false, .top: true, .bottom: true]
        s.customKeys = [.left: CustomKeys(up: KeyCombo(keyCode: 30, modifiers: KeyCombo.commandFlag), down: nil)]
        s.hapticsEnabled = false
        s.soundEnabled = true
        s.soundStyle = .morse
        s.sideWidthFraction = 0.15
        s.slidePerStepMM = 6
        s.fineControlKey = .off
        s.coarseControlKey = .off
        s.hapticTick = 6
        s.menuBarClick = .openPanel
        s.brightnessDirect = true
        s.showIndicator = false
        s.showInNotch = false
        s.notchEffect = .everyStep
        s.muteSignsSide = .left
        return s
    }

    @Test func fixtureChangesEveryStoredProperty() {
        let defaults = Mirror(reflecting: HalodeckSettings()).children
        let changed = Mirror(reflecting: Self.everythingChanged()).children
        #expect(changed.count == 21, "update everythingChanged() for the new property")
        for (d, c) in zip(defaults, changed) {
            #expect(String(describing: d.value) != String(describing: c.value),
                    "everythingChanged() leaves \(d.label ?? "?") at its default")
        }
    }

    @Test func everyPropertySurvivesJSON() throws {
        let s = Self.everythingChanged()
        #expect(s.sanitized() == s)
        #expect(try JSONDecoder().decode(HalodeckSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}

@Suite struct SanitizedCollectionsTests {
    @Test func keepsCustomKeysAsSaved() {
        var s = HalodeckSettings()
        let withFn = KeyCombo(keyCode: 123, modifiers: KeyCombo.controlFlag | KeyCombo.fnFlag)
        s.customKeys = [.top: CustomKeys(up: withFn, down: nil)]
        // Nothing is filled in for other sides, and Fn is dropped only when a key is pressed.
        #expect(s.sanitized().customKeys == [.top: CustomKeys(up: withFn, down: nil)])
    }

    @Test func keepsMultiClickCornersAsSaved() {
        var s = HalodeckSettings()
        s.setCornerAction(.lockScreen, for: .bottomLeft, clicks: 2)
        #expect(s.sanitized().multiClickCorners == [.bottomLeft: [2: .lockScreen]])
        #expect(HalodeckSettings().sanitized().multiClickCorners.isEmpty)
    }
}

/// The code says "side"; saved settings keep their original keys, so older files still load and
/// newer ones stay readable by older versions.
@Suite struct StoredSideKeysTests {
    @Test func sidesAndSideWidthLoadFromTheStoredKeys() throws {
        let s = try decode(#"{"edges":{"left":"volume","top":"track"},"edgeWidthFraction":0.15,"soundEnabled":true}"#)
        #expect(s.sides[.left] == .volume)
        #expect(s.sides[.top] == .track)
        #expect(s.sideWidthFraction == 0.15)
        #expect(s.soundEnabled)
    }

    @Test func sidesAndSideWidthSaveUnderTheStoredKeys() throws {
        var s = HalodeckSettings()
        s.sides = [.left: .volume]
        s.sideWidthFraction = 0.15
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        let keys = Set(object?.keys.map { $0 } ?? [])
        #expect(keys.isSuperset(of: ["edges", "edgeWidthFraction"]))
        #expect(keys.isDisjoint(with: ["sides", "sideWidthFraction"]))
        #expect(object?["edgeWidthFraction"] as? Double == 0.15)
        #expect((object?["edges"] as? [String: String]) == ["left": "volume"])
    }
}
