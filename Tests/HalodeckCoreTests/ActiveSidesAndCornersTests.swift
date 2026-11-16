import Testing
@testable import HalodeckCore

/// A side set to Custom keys does nothing until a shortcut is recorded, so until then it isn't
/// active: a click and slide there stays an ordinary click.
@Suite struct ActiveSidesTests {
    @Test func customKeysWithoutAShortcutIsNotActive() {
        let s = HalodeckSettings()
        #expect(s.sides[.bottom] == .customKeys)
        #expect(s.activeSides == [.left: .brightness, .right: .volume, .top: .mediaSeek])
    }

    @Test func customKeysWithOneDirectionRecordedIsActive() {
        var s = HalodeckSettings()
        s.customKeys[.bottom] = CustomKeys(up: KeyCombo(keyCode: 30, modifiers: KeyCombo.commandFlag), down: nil)
        #expect(s.activeSides[.bottom] == .customKeys)
    }

    @Test func nothingIsNeverActive() {
        var s = HalodeckSettings()
        s.sides[.left] = .nothing
        #expect(s.activeSides[.left] == nil)
    }
}

@Suite struct ActiveCornersTests {
    @Test func bottomCornersAreInactiveUntilTheirAppAndKeysAreChosen() {
        let s = HalodeckSettings()
        #expect(s.corners[.bottomLeft] == .openApp(path: ""))
        #expect(s.corners[.bottomRight] == .keyCombo(.unset))
        #expect(s.activeCorners == [.topLeft, .topRight])
    }

    @Test func aCornerWithItsAppOrKeysChosenBecomesActive() {
        var s = HalodeckSettings()
        s.setCornerAction(.openApp(path: "/Applications/Notes.app"), for: .bottomLeft, clicks: 1)
        s.setCornerAction(.keyCombo(KeyCombo(keyCode: 21, modifiers: KeyCombo.commandFlag)), for: .bottomRight, clicks: 1)
        #expect(s.activeCorners == Set(Corner.allCases))
    }
}

@Suite struct CornerActionReadinessTests {
    @Test func unfinishedActionsAreNotReady() {
        #expect(!CornerAction.openApp(path: "").isReady)
        #expect(!CornerAction.keyCombo(.unset).isReady)
        #expect(!CornerAction.openLink(url: "").isReady)
        #expect(!CornerAction.runShortcut(name: "").isReady)
        #expect(!CornerAction.nothing.isReady)
        #expect(CornerAction.lockScreen.isReady)
        #expect(!KeyCombo.unset.isSet)
    }
}
