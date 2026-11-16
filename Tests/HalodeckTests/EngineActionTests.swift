import CoreGraphics
import Testing
@testable import Halodeck
import HalodeckCore

/// A swipe along the very top or bottom starts 2 mm from the border; a sideways step is 6 mm for
/// Media seek and 12 mm for Switch tab and Custom keys, counted from where the swipe started (4 mm).
@MainActor
@Suite struct SidesWithoutALevelTests {
    let top = Pad.height - 2
    let bottom = 2.0
    /// One step right, then two steps left.
    let rightThenLeftTwice = [0.0, 4, 17, -9]

    @Test func customKeysPostTheRecordedShortcutForEachDirectionWithoutFn() async {
        let next = KeyCombo(keyCode: 30, modifiers: KeyCombo.commandFlag | KeyCombo.fnFlag)
        let previous = KeyCombo(keyCode: 33, modifiers: KeyCombo.commandFlag | KeyCombo.shiftFlag | KeyCombo.fnFlag)
        let rig = Rig {
            $0.sides[.bottom] = .customKeys
            $0.customKeys[.bottom] = CustomKeys(up: next, down: previous)
            $0.swipeWithoutClick[.bottom] = true
        }
        rig.slide(y: bottom, sidewaysMM: rightThenLeftTwice)
        await drainMain()
        #expect(rig.events.keys == [.init(keyCode: 30, flags: .maskCommand),
                                    .init(keyCode: 33, flags: [.maskCommand, .maskShift]),
                                    .init(keyCode: 33, flags: [.maskCommand, .maskShift])])
        #expect(rig.events.mediaKeys.isEmpty)
    }

    @Test func mediaSeekPostsTheArrowKeys() async {
        let rig = Rig {
            $0.sides[.top] = .mediaSeek
            $0.swipeWithoutClick[.top] = true
        }
        rig.slide(y: top, sidewaysMM: [0, 4, 11, -2])   // one step right, two left
        await drainMain()
        #expect(rig.events.keys == [.init(keyCode: KeyPress.rightArrow, flags: []),
                                    .init(keyCode: KeyPress.leftArrow, flags: []),
                                    .init(keyCode: KeyPress.leftArrow, flags: [])])
    }

    @Test func switchTabPostsControlTabAndControlShiftTab() async {
        let rig = Rig {
            $0.sides[.top] = .switchTab
            $0.swipeWithoutClick[.top] = true
        }
        rig.slide(y: top, sidewaysMM: rightThenLeftTwice)
        await drainMain()
        #expect(rig.events.keys == [.init(keyCode: KeyPress.tab, flags: .maskControl),
                                    .init(keyCode: KeyPress.tab, flags: [.maskControl, .maskShift]),
                                    .init(keyCode: KeyPress.tab, flags: [.maskControl, .maskShift])])
    }

    /// Top and bottom have their ticks off by default; the level sides keep theirs.
    @Test func aSideWithTicksOffIsSilentWhileALevelSideTicks() async {
        let rig = Rig {
            $0.swipeWithoutClick[.top] = true
            $0.soundEnabled = true
        }
        rig.slide(y: top, sidewaysMM: [0, 4, 11, 17])   // two seek steps
        await drainMain()
        #expect(rig.events.keys.count == 2)
        #expect(rig.feedback.ticks.isEmpty)
        #expect(rig.feedback.sounds.isEmpty)

        rig.lift()
        rig.slide(finger: 2, x: 0.95, [40, 43.5, 52])   // two volume steps
        await drainMain()
        #expect(rig.feedback.ticks == [1, 1])
        #expect(rig.feedback.sounds.count == 2)
    }

    @Test func turningTicksOnForASideWithoutALevelTicksEveryStep() async {
        let rig = Rig {
            $0.swipeWithoutClick[.top] = true
            $0.ticksEnabled[.top] = true
            $0.soundEnabled = true
        }
        rig.slide(y: top, sidewaysMM: [0, 4, 11, 17])
        await drainMain()
        #expect(rig.feedback.ticks == [1, 1])
        // No level to read: the sound plays its middle note.
        #expect(rig.feedback.sounds == [nil, nil])
    }
}

@MainActor
@Suite struct CornerDoubleClickTests {
    func rig() -> Rig {
        Rig {
            $0.setCornerAction(.missionControl, for: .topLeft, clicks: 1)
            $0.setCornerAction(.showDesktop, for: .topLeft, clicks: 2)
        }
    }

    func click(_ rig: Rig) {
        var posted: [CGEventType] = []
        #expect(!rig.mouse(.leftMouseDown, posted: &posted))
        #expect(!rig.mouse(.leftMouseUp, posted: &posted))
        #expect(posted.isEmpty)
    }

    @Test func oneClickRunsAfterTheDoubleClickInterval() async {
        let rig = rig()
        rig.slide(x: 0.05, [80])
        click(rig)
        await drainMain()
        #expect(rig.actions.ran.isEmpty)

        rig.input.now += rig.input.doubleClickInterval - 0.05
        rig.engine.tick()
        #expect(rig.actions.ran.isEmpty)
        #expect(rig.hud.bursts.isEmpty)

        rig.input.now += 0.1
        rig.engine.tick()
        #expect(rig.actions.ran == [.missionControl])
        #expect(rig.hud.bursts == [.init(corner: .topLeft, clicks: 1)])
    }

    @Test func aSecondClickRunsTheDoubleClickActionAtOnce() async {
        let rig = rig()
        rig.slide(x: 0.05, [80])
        click(rig)
        await drainMain()
        rig.input.now += 0.1
        click(rig)
        await drainMain()
        #expect(rig.actions.ran == [.showDesktop])
        #expect(rig.hud.bursts == [.init(corner: .topLeft, clicks: 2)])

        rig.input.now += 1
        rig.engine.tick()
        #expect(rig.actions.ran == [.showDesktop])
    }
}

/// The right side (volume) at x = 0.95: a swipe starts after 3 mm and steps every 4 mm.
@MainActor
@Suite struct FineControlAndSwipeTests {
    @Test func holdingOptionGivesQuarterSteps() async {
        let rig = Rig()
        rig.input.isOptionHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])   // two steps up
        await drainMain()
        #expect(rig.levels.level == 0.5 + 2.0 / 64)
        #expect(rig.hud.levels == [0.5 + 2.0 / 64])
    }

    @Test func withFineControlOffOptionChangesNothing() async {
        let rig = Rig { $0.fineControlKey = .off }
        rig.input.isOptionHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.levels.level == 0.5 + 2.0 / 16)
    }

    @Test func holdingShiftMovesToTheNextEighths() async {
        let rig = Rig(volume: 0.55) { $0.soundEnabled = true }
        rig.input.isShiftHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])   // two steps up
        await drainMain()
        #expect(rig.levels.level == 0.75)
        #expect(rig.hud.levels == [0.75])
        // One tick and one note per step taken.
        #expect(rig.feedback.ticks == [1, 1])
        #expect(rig.feedback.sounds == [0.625, 0.75])
    }

    @Test func shiftStopsAtTheTopWithOneTickAndABump() async {
        let rig = Rig(volume: 0.95)
        rig.input.isShiftHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.levels.level == 1)
        #expect(rig.feedback.ticks == [1])
        #expect(rig.hud.bumps == [true])
    }

    @Test func shiftWithMediaKeysPressesASixteenthKeyUntilTheNextEighth() async {
        let rig = Rig(volume: 0.5625)
        rig.hud.showsInNotch = false
        rig.input.isShiftHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])   // 0.5625 → 0.625 (one key) → 0.75 (two keys)
        await drainMain()
        #expect(rig.events.mediaKeys == [.volumeUp, .volumeUp, .volumeUp])
        #expect(rig.events.fineFlags == [false, false, false])
        #expect(rig.feedback.ticks == [1, 1])
    }

    @Test func withCoarseControlOffShiftChangesNothing() async {
        let rig = Rig { $0.coarseControlKey = .off }
        rig.input.isShiftHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.levels.level == 0.5 + 2.0 / 16)
    }

    /// Fine control is the more deliberate of the two: with Option and Shift held, it wins.
    @Test func withOptionAndShiftHeldFineControlWins() async {
        let rig = Rig()
        rig.input.isOptionHeld = true
        rig.input.isShiftHeld = true
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.levels.level == 0.5 + 2.0 / 64)
    }

    @Test func shiftOnSeekAndTabSidesChangesNothing() async {
        let rig = Rig {
            $0.sides[.top] = .mediaSeek
            $0.sides[.bottom] = .switchTab
            $0.swipeWithoutClick[.top] = true
            $0.swipeWithoutClick[.bottom] = true
        }
        rig.input.isShiftHeld = true
        rig.slide(y: Pad.height - 2, sidewaysMM: [0, 4, 11, 17])   // two seek steps right
        await drainMain()
        #expect(rig.events.keys == [.init(keyCode: KeyPress.rightArrow, flags: []),
                                    .init(keyCode: KeyPress.rightArrow, flags: [])])
        #expect(rig.hud.texts.last == "Forward ×2")

        rig.lift()
        rig.slide(finger: 2, y: 2, sidewaysMM: [0, 4, 17])   // one tab step right
        await drainMain()
        #expect(rig.events.keys.last == .init(keyCode: KeyPress.tab, flags: .maskControl))
        #expect(rig.events.keys.count == 3)
        #expect(rig.levels.level == 0.5)
    }

    @Test func perSideSwipeSettingsBecomeTheSwipeSides() {
        var s = HalodeckSettings()
        s.swipeWithoutClick = [.left: true, .right: false, .top: true, .bottom: false]
        #expect(Engine.makeConfig(s, brightnessAvailable: true).swipeSides == [.left, .top])
    }

    @Test func onlyASideWithSwipeOnStartsOnAPlainSwipe() async {
        let rig = Rig { $0.swipeWithoutClick = [.left: true, .right: false, .top: false, .bottom: false] }
        rig.slide(x: 0.95, [40, 43.5, 52])   // right side: swipe off
        await drainMain()
        #expect(rig.levels.level == 0.5)
        #expect(rig.hud.levels.isEmpty)

        rig.lift()
        rig.slide(finger: 2, x: 0.05, [40, 43.5, 52])   // left side: swipe on
        await drainMain()
        #expect(rig.levels.brightnessLevel == 0.5 + 2.0 / 16)
        #expect(rig.hud.levels == [0.5 + 2.0 / 16])
    }
}
