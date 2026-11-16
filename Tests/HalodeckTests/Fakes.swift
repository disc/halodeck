import AppKit
import CoreGraphics
import Foundation
@testable import Halodeck
import HalodeckCore

// Fakes for the system services `Engine` drives: they record what the engine asked for and touch
// nothing on the real Mac (no events posted, no pointer frozen, no tap, no touch stream).

@MainActor
final class FakeLevels: LevelControl {
    var level: Double? = 0.5
    var volumeReads = 0
    var canSetVolume = true
    var isMuted: Bool? = false
    var brightnessAvailable = true
    var brightnessLevel: Double? = 0.5
    var keyboardLightAvailable = false
    /// What `watchOutput` was given: call it after changing `isMuted` or `level`, as CoreAudio would.
    var outputChanged: (@MainActor @Sendable () -> Void)?

    func volume() -> Double? {
        volumeReads += 1
        return level
    }
    func setVolume(_ value: Double) { level = min(1, max(0, value)) }
    func setMuted(_ muted: Bool) { isMuted = muted }
    func watchOutput(_ onChange: @escaping @MainActor @Sendable () -> Void) { outputChanged = onChange }
    func brightness() -> Double? { brightnessLevel }
    func setBrightness(_ value: Double) { brightnessLevel = min(1, max(0, value)) }
    func refreshDisplays() {}
    func keyboardLight() -> Double? { nil }
    func setKeyboardLight(_ value: Double) {}
}

@MainActor
final class FakeEvents: EventPosting {
    struct Key: Equatable {
        let keyCode: UInt16
        let flags: CGEventFlags
    }
    var mediaKeys: [MediaKey] = []
    var fineFlags: [Bool] = []
    var keys: [Key] = []
    var sessionPosts: [CGEventType] = []

    func press(_ key: MediaKey, fine: Bool) {
        mediaKeys.append(key)
        fineFlags.append(fine)
    }
    func post(keyCode: UInt16, flags: CGEventFlags) { keys.append(Key(keyCode: keyCode, flags: flags)) }
    func postToSession(_ event: CGEvent) { sessionPosts.append(event.type) }
}

@MainActor
final class FakeFeedback: Feedback {
    var ticks: [Int] = []
    var sounds: [Double?] = []

    func prepare(devices: [Int: MTDeviceRef]) {}
    func tick(device: Int, id: Int32) { ticks.append(device) }
    func play(_ style: SoundStyle, level: Double?) { sounds.append(level) }
}

@MainActor
final class FakeActions: CornerActionRunning {
    var ran: [CornerAction] = []
    func run(_ action: CornerAction) { ran.append(action) }
}

@MainActor
final class FakeHUD: HUDPresenting {
    var showsInNotch = true
    var levels: [Double] = []
    var texts: [String] = []
    /// The direction of each step shown (true = up/right).
    var directions: [Bool] = []
    /// Each end-of-range bump: true when the slide ran into 100% (the notch's right side), false for 0%.
    var bumps: [Bool] = []
    struct Burst: Equatable {
        let corner: Corner
        let clicks: Int
    }
    var bursts: [Burst] = []
    var screenChanges = 0
    var microphoneMuted: Bool?
    var soundSilent: Bool? { soundSilentUpdates.last }
    var soundSilentUpdates: [Bool] = []

    func configure(showInNotch: Bool, effect: NotchEffect, muteSigns: MuteSignsSide) {}
    func greet(on: Bool) {}
    func show(symbol: String, content: HUDContent, up: Bool) {
        switch content {
        case let .level(level): levels.append(level)
        case let .text(text): texts.append(text)
        }
        directions.append(up)
    }
    func show(appIcon: NSImage, text: String) { texts.append(text) }
    func bump(atTop: Bool) { bumps.append(atTop) }
    func burst(corner: Corner, clicks: Int) { bursts.append(Burst(corner: corner, clicks: clicks)) }
    func hostBursts() {}
    func setMicrophoneMuted(_ muted: Bool) { microphoneMuted = muted }
    func setSoundSilent(_ silent: Bool) { soundSilentUpdates.append(silent) }
    func screensChanged() { screenChanges += 1 }
}

/// Called from the multitouch and tap paths too, so its record is behind a lock.
final class FakePointer: PointerFreezing {
    struct Record: Sendable {
        var locationReads = 0
        var frozenAt: CGPoint?
        var freezes = 0
    }
    let record = Locked(Record())
    static let position = CGPoint(x: 100, y: 200)

    func location() -> CGPoint? {
        record.withLock { $0.locationReads += 1 }
        return Self.position
    }
    func freeze(at point: CGPoint) { record.withLock { $0.frozenAt = point; $0.freezes += 1 } }
    func unfreeze() { record.withLock { $0.frozenAt = nil } }
    func pin(_ location: CGPoint) {}
    func heartbeat() {}
}

@MainActor
final class FakeTap: EventTapControl {
    var running = false
    var onDisabled: (@Sendable () -> Void)?

    func start(handler: @escaping EventTap.Handler, onDisabled: @escaping @Sendable () -> Void) -> Bool {
        running = true
        self.onDisabled = onDisabled
        return true
    }
    func stop() { running = false }
}

@MainActor
final class FakeTouches: TouchStream {
    var running = false
    var hasDevices = true

    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void,
               onDevicesChanged: @escaping @MainActor ([Int: MTDeviceRef]) -> Void) { running = true }
    func stop() { running = false }
}

@MainActor
final class FakeAccessibility: AccessibilityAccess {
    var isGranted = true
    func watch(_ onChange: @escaping @MainActor @Sendable () -> Void) {}
}

@MainActor
final class FakeInput: InputState {
    var now: TimeInterval = 1000
    var doubleClickInterval: TimeInterval = 0.3
    var isOptionHeld = false
    var isShiftHeld = false
}

/// An engine wired to fakes, with settings applied (so it is on unless `enabled` is false).
@MainActor
final class Rig {
    let levels = FakeLevels()
    let events = FakeEvents()
    let feedback = FakeFeedback()
    let actions = FakeActions()
    let hud = FakeHUD()
    let pointer = FakePointer()
    let tap = FakeTap()
    let touches = FakeTouches()
    let accessibility = FakeAccessibility()
    let input = FakeInput()
    let engine: Engine

    /// Default settings with a swipe on the volume side, then `edit`. `live` also starts the engine's watchers (all on fakes but the
    /// notification observers); `muted` and `volume` are the output's mute switch and volume before the engine starts.
    init(live: Bool = false, muted: Bool? = false, volume: Double? = 0.5,
         _ edit: (inout HalodeckSettings) -> Void = { _ in }) {
        levels.isMuted = muted
        levels.level = volume
        let store = SettingsStore(defaults: UserDefaults(suiteName: "halodeck-tests-\(UUID().uuidString)")!)
        var settings = store.settings
        // The tests slide the right (volume) side without clicking: let it start on a swipe
        // (by default every side needs a click).
        settings.swipeWithoutClick[.right] = true
        edit(&settings)
        store.settings = settings
        engine = Engine(store: store,
                        services: EngineServices(levels: levels, events: events, feedback: feedback,
                                                 actions: actions, hud: hud, pointer: pointer, tap: tap,
                                                 touches: touches, accessibility: accessibility,
                                                 input: input),
                        live: live)
        engine.apply(settings)
    }

    /// Feeds frames of one finger on device 1 at `x`, one per `y` (millimetres from the bottom).
    func slide(finger: Int32 = 1, x: Double, _ ys: [Double]) {
        for y in ys { frame([TouchPoint(id: finger, normalizedX: x, xMM: x * Pad.width, yMM: y)]) }
    }

    /// Feeds frames of one finger on device 1 at `y` millimetres from the bottom, starting at the
    /// middle and moved sideways by each of `mm` (right is positive).
    func slide(finger: Int32 = 1, y: Double, sidewaysMM mm: [Double]) {
        for dx in mm {
            let x = 0.5 + dx / Pad.width
            frame([TouchPoint(id: finger, normalizedX: x, xMM: x * Pad.width, yMM: y)])
        }
    }

    func lift() { frame([]) }

    func frame(_ touches: [TouchPoint]) {
        engine.handleFrame(TouchFrame(device: 1, padHeightMM: Pad.height, touches: touches, time: input.now))
    }

    /// Sends a mouse event through the engine as the event tap would; returns true if it passed.
    /// Events the engine posts ahead of it land in `posted`.
    @discardableResult
    func mouse(_ type: CGEventType, posted: inout [CGEventType]) -> Bool {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 5, y: 5),
                            mouseButton: .left)!
        var sent: [CGEventType] = []
        let pass = engine.handleEvent(type, event) { sent.append($0.type) }
        posted += sent
        return pass
    }
}

enum Pad {
    static let width = 142.7
    static let height = 85.1
}

/// Lets everything already queued on the main queue run (outputs from the touch and tap threads
/// reach the engine that way, in order).
@MainActor
func drainMain() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
