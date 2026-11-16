import CoreGraphics
import Testing
@testable import Halodeck
import HalodeckCore

/// The right side (volume by default) is at x = 0.95; a swipe starts after 3 mm and steps every 4 mm.
@MainActor
@Suite struct EngineTests {
    @Test func stepsSetTheVolumeAndShowTheLevel() async {
        let rig = Rig()
        rig.slide(x: 0.95, [40, 43.5, 52])   // began, then 2 steps up
        await drainMain()
        #expect(rig.levels.level == 0.5 + 2.0 / 16)
        #expect(rig.hud.levels == [0.5 + 2.0 / 16])
        #expect(rig.feedback.ticks == [1, 1])
        #expect(rig.events.mediaKeys.isEmpty)
        #expect(rig.pointer.record.withLock { $0.frozenAt } == FakePointer.position)
    }

    @Test func theStepsDirectionReachesTheIndicator() async {
        let rig = Rig()
        rig.slide(x: 0.95, [52, 48.5, 40])   // began, then 2 steps down
        await drainMain()
        #expect(rig.hud.levels == [0.5 - 2.0 / 16])
        #expect(rig.hud.directions == [false])
    }

    @Test func withoutTheNotchStepsPressTheVolumeKeys() async {
        let rig = Rig()
        rig.hud.showsInNotch = false
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.events.mediaKeys == [.volumeUp, .volumeUp])
        #expect(rig.levels.level == 0.5)
    }

    @Test func aVolumeStepReadsTheLevelOnce() async {
        let rig = Rig()
        rig.slide(x: 0.95, [40, 43.5, 48])   // began, then 1 step
        await drainMain()
        #expect(rig.levels.volumeReads == 1)
    }

    @Test func slidingPastFullBumpsTheTop() async {
        let rig = Rig()
        rig.levels.level = 1
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.hud.bumps == [true])
        #expect(rig.feedback.ticks.isEmpty)
        #expect(rig.levels.level == 1)
    }

    @Test func slidingPastZeroBumpsTheBottom() async {
        let rig = Rig()
        rig.levels.level = 0
        rig.slide(x: 0.95, [52, 48.5, 40])
        await drainMain()
        #expect(rig.hud.bumps == [false])
        #expect(rig.feedback.ticks.isEmpty)
    }

    /// Along the top or bottom edge, right is up: running into 100% bumps the notch's right side,
    /// into 0% its left.
    @Test func slidingSidewaysIntoEitherEndBumpsThatEnd() async {
        for (level, mm, top) in [(1.0, [0.0, 4, 30], true), (0.0, [0.0, -4, -30], false)] {
            let rig = Rig(volume: level) {
                $0.sides[.top] = .volume
                $0.swipeWithoutClick[.top] = true
            }
            rig.slide(y: Pad.height - 2, sidewaysMM: mm)
            await drainMain()
            #expect(!rig.hud.bumps.isEmpty)
            #expect(rig.hud.bumps.allSatisfy { $0 == top })
            #expect(rig.levels.level == level)
        }
    }

    // MARK: Bumping once per push

    /// Millimetres along the right side for a slide toward 100% (`top`) or, mirrored, toward 0%.
    private func toward(_ top: Bool, _ ys: [Double]) -> [Double] { top ? ys : ys.map { 92 - $0 } }

    @Test(arguments: [true, false]) func pushingOnPastTheEndBumpsOnce(top: Bool) async {
        let rig = Rig(volume: top ? 1 : 0)
        rig.slide(x: 0.95, toward(top, [40, 43.5, 48, 52, 56, 60]))   // began, then 4 steps into the end
        await drainMain()
        #expect(rig.hud.bumps == [top])
        #expect(rig.levels.level == (top ? 1 : 0))
    }

    @Test(arguments: [true, false]) func reversingThenPushingIntoTheEndBumpsAgain(top: Bool) async {
        let rig = Rig(volume: top ? 1 : 0)
        // Began; 2 steps into the end; 1 step back; 1 step back to the end; 2 steps past it.
        rig.slide(x: 0.95, toward(top, [40, 43.5, 48, 52, 47, 52, 56, 60]))
        await drainMain()
        #expect(rig.hud.bumps == [top, top])
        #expect(rig.levels.level == (top ? 1 : 0))
    }

    @Test(arguments: [true, false]) func aNewGestureBumpsAgain(top: Bool) async {
        let rig = Rig(volume: top ? 1 : 0)
        rig.slide(finger: 1, x: 0.95, toward(top, [40, 43.5, 48, 52]))   // 2 steps into the end
        await drainMain()   // the steps act while the gesture is still on
        rig.lift()
        rig.slide(finger: 2, x: 0.95, toward(top, [40, 43.5, 48, 52]))
        await drainMain()
        #expect(rig.hud.bumps == [top, top])
    }

    @Test func aStepWithinRangeDoesNotBump() async {
        let rig = Rig()
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.hud.bumps.isEmpty)
    }

    /// Outputs reach the main actor later: steps still queued from a finished gesture must not
    /// act while the next gesture runs.
    @Test func queuedStepsOfAnEarlierGestureAreDropped() async {
        let rig = Rig()
        rig.slide(finger: 1, x: 0.95, [40, 43.5, 52])   // gesture A: 2 steps
        rig.lift()
        rig.slide(finger: 2, x: 0.95, [40, 43.5, 48])   // gesture B: 1 step
        await drainMain()
        #expect(rig.levels.level == 0.5 + 1.0 / 16)
    }

    // MARK: On and off

    @Test func anEngineThatIsOffIgnoresFramesAndReadsNoPointer() async {
        let rig = Rig { $0.enabled = false }
        #expect(rig.engine.state == .off)
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.levels.level == 0.5)
        #expect(rig.hud.levels.isEmpty)
        #expect(rig.pointer.record.withLock { $0.locationReads } == 0)
    }

    @Test func theTouchStreamRunsOnlyWhileOn() {
        let rig = Rig { $0.enabled = false }
        #expect(!rig.touches.running)
        #expect(!rig.tap.running)
        rig.engine.setEnabled(true)
        #expect(rig.touches.running && rig.tap.running)
        #expect(rig.engine.state == .running)
        rig.engine.setEnabled(false)
        #expect(!rig.touches.running && !rig.tap.running)
    }

    @Test func withoutAccessibilityTheEngineWaits() {
        let rig = Rig { $0.enabled = false }
        rig.accessibility.isGranted = false
        rig.engine.setEnabled(true)
        #expect(rig.engine.state == .needsAccessibility)
        #expect(!rig.touches.running && !rig.tap.running)
    }

    @Test func noTrackpadIsReported() {
        let rig = Rig { $0.enabled = false }
        rig.touches.hasDevices = false
        rig.engine.setEnabled(true)
        #expect(rig.engine.state == .noTrackpad)
    }

    // MARK: Clicks

    @Test func aCornerClickRunsItsAction() async {
        let rig = Rig { $0.setCornerAction(.missionControl, for: .topLeft, clicks: 1) }
        rig.slide(x: 0.05, [80])
        var posted: [CGEventType] = []
        #expect(!rig.mouse(.leftMouseDown, posted: &posted))
        #expect(!rig.mouse(.leftMouseUp, posted: &posted))
        await drainMain()
        #expect(rig.actions.ran == [.missionControl])
        #expect(rig.hud.bursts == [.init(corner: .topLeft, clicks: 1)])
        #expect(posted.isEmpty)
    }

    @Test func aPlainClickInAStripIsReplayedDownThenUp() {
        let rig = Rig()
        rig.slide(x: 0.95, [40])
        var posted: [CGEventType] = []
        #expect(!rig.mouse(.leftMouseDown, posted: &posted))
        #expect(!rig.mouse(.leftMouseUp, posted: &posted))
        #expect(posted == [.leftMouseDown, .leftMouseUp])
    }

    @Test func aDisabledTapDropsTheHeldClick() async {
        let rig = Rig()
        rig.slide(x: 0.95, [40])
        var posted: [CGEventType] = []
        #expect(!rig.mouse(.leftMouseDown, posted: &posted))
        rig.tap.onDisabled?()
        #expect(rig.mouse(.leftMouseUp, posted: &posted))   // the app already got the rest of the click
        await drainMain()
        #expect(posted.isEmpty)
        #expect(rig.events.sessionPosts.isEmpty)
    }

    @Test func switchingOffWhileHoldingPostsTheHeldClick() {
        let rig = Rig()
        rig.slide(x: 0.95, [40])
        var posted: [CGEventType] = []
        #expect(!rig.mouse(.leftMouseDown, posted: &posted))
        rig.engine.setEnabled(false)
        #expect(rig.events.sessionPosts == [.leftMouseDown])
    }

    // MARK: Sound off (muted or at 0%)

    @Test func soundMutedBeforeLaunchShowsItsSign() {
        let rig = Rig(live: true, muted: true)
        #expect(rig.hud.soundSilent == true)
    }

    @Test func aMuteChangeReachesTheHUD() {
        let rig = Rig(live: true)
        #expect(rig.hud.soundSilent == false)
        // Muted elsewhere (the mute key, Control Center): CoreAudio reports it.
        rig.levels.isMuted = true
        rig.levels.outputChanged?()
        #expect(rig.hud.soundSilent == true)
        rig.levels.isMuted = false
        rig.levels.outputChanged?()
        #expect(rig.hud.soundSilent == false)
    }

    @Test func anOutputWithoutAMuteSwitchShowsNoSign() {
        let rig = Rig(live: true, muted: nil)
        #expect(rig.hud.soundSilent == false)
    }

    @Test func aZeroVolumeShowsTheSoundSign() {
        let rig = Rig(live: true)
        rig.levels.level = 0
        rig.levels.outputChanged?()
        #expect(rig.hud.soundSilent == true)
    }

    @Test func raisingTheVolumeFromZeroHidesTheSign() {
        let rig = Rig(live: true, volume: 0)
        #expect(rig.hud.soundSilent == true)
        rig.levels.level = 0.25
        rig.levels.outputChanged?()
        #expect(rig.hud.soundSilent == false)
    }

    @Test func zeroVolumeAtLaunchShowsTheSign() {
        let rig = Rig(live: true, volume: 0)
        #expect(rig.hud.soundSilent == true)
    }

    /// An output without a volume control (HDMI, for example) shows the sign only while muted.
    @Test func anOutputWithoutAVolumeControlShowsTheSignOnlyWhenMuted() {
        let rig = Rig(live: true, volume: nil)
        #expect(rig.hud.soundSilent == false)
        rig.levels.isMuted = true
        rig.levels.outputChanged?()
        #expect(rig.hud.soundSilent == true)
    }

    /// Halodeck's own slide to 0% shows the sign at once, without waiting for CoreAudio; CoreAudio's
    /// report that follows changes nothing.
    @Test func slidingTheVolumeToZeroShowsTheSignAtOnce() async {
        let rig = Rig(live: true, volume: 2.0 / 16)
        #expect(rig.hud.soundSilentUpdates == [false])
        rig.slide(x: 0.95, [52, 48.5, 40])   // began, then 2 steps down
        await drainMain()
        #expect(rig.levels.level == 0)
        #expect(rig.hud.soundSilentUpdates == [false, true])
        rig.levels.outputChanged?()
        #expect(rig.hud.soundSilentUpdates == [false, true])
    }

    @Test func slidingTheVolumeUpFromZeroHidesTheSignAtOnce() async {
        let rig = Rig(live: true, volume: 0)
        rig.slide(x: 0.95, [40, 43.5, 48])   // began, then 1 step up
        await drainMain()
        #expect(rig.hud.soundSilentUpdates == [true, false])
    }

    @Test func aSlideAboveZeroDoesNotTouchTheSign() async {
        let rig = Rig(live: true)
        rig.slide(x: 0.95, [40, 43.5, 52])
        await drainMain()
        #expect(rig.hud.soundSilentUpdates == [false])
    }

    /// The snapshot mode and the other tests build an inert engine: it doesn't watch the output.
    @Test func anInertEngineDoesNotWatchTheOutput() {
        let rig = Rig(muted: true)
        #expect(rig.levels.outputChanged == nil)
        #expect(rig.hud.soundSilent == nil)
    }

    @Test func aScreenChangeUpdatesBrightnessAvailability() async {
        let rig = Rig()
        #expect(rig.engine.brightnessAvailable)
        rig.levels.brightnessAvailable = false
        rig.engine.screensChanged()
        #expect(!rig.engine.brightnessAvailable)
        #expect(rig.hud.screenChanges == 1)
        // The left side (brightness) no longer slides.
        rig.slide(x: 0.05, [40, 43.5, 52])
        await drainMain()
        #expect(rig.hud.levels.isEmpty)
        #expect(rig.pointer.record.withLock { $0.freezes } == 0)
    }
}

@MainActor
@Suite struct HUDAnnouncerTests {
    @Test func levelsAreNamedBySymbol() {
        #expect(HUDAnnouncer.text(symbol: "speaker.wave.2.fill", content: .level(0.4)) == "Volume 40%")
        #expect(HUDAnnouncer.text(symbol: "sun.max.fill", content: .level(0.755)) == "Brightness 76%")
        #expect(HUDAnnouncer.text(symbol: "light.max", content: .level(1)) == "Keyboard light 100%")
        #expect(HUDAnnouncer.text(symbol: "square.on.square", content: .text("Next tab ×2")) == "Next tab ×2")
    }
}

@Suite struct ActionRunnerTests {
    @Test func shortcutNamesCannotBeReadAsOptions() {
        #expect(ActionRunner.shortcutArguments("-h") == ["run", "--", "-h"])
    }
}
