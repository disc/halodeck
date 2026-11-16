import AppKit
import HalodeckCore

// The system services `Engine` drives, as small protocols so tests can swap in fakes.

/// Volume, display brightness and the keyboard light as exact 0...1 levels.
@MainActor
protocol LevelControl {
    /// The default output's volume can be set directly (HDMI outputs, for example, can't).
    var canSetVolume: Bool { get }
    /// The default output's volume; nil when it has no volume control.
    func volume() -> Double?
    /// Sets the output volume; turning it up unmutes, like the volume keys do.
    func setVolume(_ value: Double)
    /// Whether the output is muted; nil when it has no mute switch.
    var isMuted: Bool? { get }
    func setMuted(_ muted: Bool)
    /// Calls `onChange` (on the main actor) whenever the output's mute switch or volume may have
    /// changed: by Halodeck, the keys, Control Center or another app, or because the default output
    /// changed. Read `isMuted` and `volume()` for the new state.
    func watchOutput(_ onChange: @escaping @MainActor @Sendable () -> Void)

    /// An active built-in display, whose brightness Halodeck can read and set.
    var brightnessAvailable: Bool { get }
    func brightness() -> Double?
    func setBrightness(_ value: Double)
    func refreshDisplays()

    var keyboardLightAvailable: Bool { get }
    func keyboardLight() -> Double?
    func setKeyboardLight(_ value: Double)
}

@MainActor
protocol EventPosting {
    /// A media key, the way the keyboard sends it (macOS shows its own indicator).
    func press(_ key: MediaKey, fine: Bool)
    func post(keyCode: UInt16, flags: CGEventFlags)
    /// A held mouse event let through late, into the session's event stream.
    func postToSession(_ event: CGEvent)
}

@MainActor
protocol Feedback {
    /// The trackpads changed: open their haptic actuators.
    func prepare(devices: [Int: MTDeviceRef])
    func tick(device: Int, id: Int32)
    func play(_ style: SoundStyle, level: Double?)
}

@MainActor
protocol CornerActionRunning {
    func run(_ action: CornerAction)
}

/// The pill / notch indicator (`HUDController`).
@MainActor
protocol HUDPresenting {
    /// True when the indicator grows out of the notch (a notch Mac with "Show in the notch" on).
    var showsInNotch: Bool { get }
    func configure(showInNotch: Bool, effect: NotchEffect, muteSigns: MuteSignsSide)
    /// Halodeck was switched on or off.
    func greet(on: Bool)
    /// Shows `content` beside `symbol`. `up` is the direction of the step shown (up/right or
    /// down/left): the notch's light runs that way.
    func show(symbol: String, content: HUDContent, up: Bool)
    func show(appIcon: NSImage, text: String)
    /// A level slide ran into 100% (`atTop`: the notch's right side pushes out) or 0% (its left side).
    func bump(atTop: Bool)
    func burst(corner: Corner, clicks: Int)
    func hostBursts()
    /// The microphone was muted or unmuted with Halodeck: the muted sign by the notch follows.
    func setMicrophoneMuted(_ muted: Bool)
    /// The sound output went off (muted or at 0%) or back on, wherever that happened: the sound-off
    /// sign by the notch follows.
    func setSoundSilent(_ silent: Bool)
    func screensChanged()
}

extension HUDPresenting {
    func show(symbol: String, level: Double, up: Bool) { show(symbol: symbol, content: .level(level), up: up) }
    func show(symbol: String, text: String, up: Bool = true) { show(symbol: symbol, content: .text(text), up: up) }
}

/// Holds the pointer still during a gesture. Called from the main actor and from the event-tap thread.
protocol PointerFreezing: Sendable {
    /// Where the pointer is now (a WindowServer round trip).
    func location() -> CGPoint?
    func freeze(at point: CGPoint)
    /// Puts the pointer back where it was, and lets finger movement move it again.
    func unfreeze()
    /// While frozen: moves the pointer back if `location` is off the frozen point.
    func pin(_ location: CGPoint)
    /// The main thread is alive: keeps the freeze from being undone by the watchdog.
    func heartbeat()
}

@MainActor
protocol EventTapControl {
    /// `handler` runs on the tap's own thread with the event's type, the event, and a function that
    /// posts an event ahead of the one being handled; it returns true to let the event through.
    /// `onDisabled` runs there too when macOS disabled the tap. False when the tap can't be created.
    func start(handler: @escaping EventTap.Handler, onDisabled: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

@MainActor
protocol TouchStream {
    /// `onFrame` runs on the MultitouchSupport thread; `onDevicesChanged` on the main actor.
    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void,
               onDevicesChanged: @escaping @MainActor ([Int: MTDeviceRef]) -> Void)
    func stop()
    var hasDevices: Bool { get }
}

/// The Accessibility permission the event tap needs.
@MainActor
protocol AccessibilityAccess {
    var isGranted: Bool { get }
    /// Calls `onChange` (on the main actor) whenever the permission may have changed.
    func watch(_ onChange: @escaping @MainActor @Sendable () -> Void)
}

@MainActor
protocol InputState {
    /// Seconds since the Mac started, the clock touch frames carry.
    var now: TimeInterval { get }
    /// How quickly a second click must follow to make a double click (System Settings).
    var doubleClickInterval: TimeInterval { get }
    var isOptionHeld: Bool { get }
    var isShiftHeld: Bool { get }
}

@MainActor
struct EngineServices {
    var levels: any LevelControl
    var events: any EventPosting
    var feedback: any Feedback
    var actions: any CornerActionRunning
    var hud: any HUDPresenting
    var pointer: any PointerFreezing
    var tap: any EventTapControl
    var touches: any TouchStream
    var accessibility: any AccessibilityAccess
    var input: any InputState

    static func live(hud: HUDController) -> EngineServices {
        let levels = Levels()
        return EngineServices(levels: levels, events: LiveEvents(), feedback: LiveFeedback(),
                              actions: ActionRunner(levels: levels, hud: hud), hud: hud,
                              pointer: PointerFreeze.shared, tap: EventTap(), touches: MultitouchManager(),
                              accessibility: AccessibilityWatcher(), input: LiveInput())
    }
}

struct LiveEvents: EventPosting {
    func press(_ key: MediaKey, fine: Bool) { MediaKeys.press(key, fine: fine) }
    func post(keyCode: UInt16, flags: CGEventFlags) { KeyPress.post(keyCode: keyCode, flags: flags) }
    func postToSession(_ event: CGEvent) {
        event.tagAsHalodeck()
        event.post(tap: .cgSessionEventTap)
    }
}

struct LiveInput: InputState {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var doubleClickInterval: TimeInterval { NSEvent.doubleClickInterval }
    var isOptionHeld: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) }
    var isShiftHeld: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) }
}

struct LiveFeedback: Feedback {
    func prepare(devices: [Int: MTDeviceRef]) { Haptics.prepare(devices: devices) }
    func tick(device: Int, id: Int32) { Haptics.tick(device: device, id: id) }
    func play(_ style: SoundStyle, level: Double?) { SoundTicks.play(style, level: level) }
}

/// Notification observers, removed when the bag goes away with the object that owns it.
final class ObserverBag {
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func observe(_ center: NotificationCenter, _ name: Notification.Name,
                 _ block: @escaping @MainActor @Sendable () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { block() }
        }
        tokens.append((center, token))
    }

    func removeAll() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens = []
    }

    deinit { removeAll() }
}
