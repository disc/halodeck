import AppKit
import Combine
import HalodeckCore
import Observation
import os

enum EngineState: Equatable { case off, running, needsAccessibility, noTrackpad }

/// Glues the trackpad, the event tap and the pure `Recognizer` together and carries out its decisions
/// through `EngineServices`.
///
/// Threads: `handleFrame` runs on the MultitouchSupport thread and `handleEvent` / `tapWasDisabled`
/// on the event-tap thread; those touch nothing but the lock-protected `shared` and the pointer
/// freeze, and hand every other effect to the main actor, where the rest of the engine runs.
@MainActor
@Observable
final class Engine {
    private(set) var state: EngineState = .off
    /// An active built-in display: brightness sides work. Follows screen changes.
    private(set) var brightnessAvailable: Bool

    @ObservationIgnored private let services: EngineServices
    @ObservationIgnored nonisolated private let pointer: any PointerFreezing
    @ObservationIgnored private var settingsSink: AnyCancellable?
    private let observers = ObserverBag()
    private let log = Logger(subsystem: "io.github.disc.halodeck", category: "engine")

    struct Stamped: Sendable {
        let output: RecognizerOutput
        let gesture: Int
    }

    /// A held-back mouse-down. `CGEvent` isn't `Sendable`; this one is a private copy that lives in
    /// `shared` and is only touched under its lock, until one thread takes it out to post it or
    /// read its location, after which no other thread can reach it.
    struct HeldEvent: @unchecked Sendable {
        let event: CGEvent
    }

    /// Everything the multitouch thread, the event-tap thread and the main actor share.
    struct Shared: Sendable {
        var recognizer: Recognizer
        var active = false
        var knownFingers: [Int: Set<Int32>] = [:]
        var landingCursor: [Int: [Int32: CGPoint]] = [:]
        /// The click held back while Halodeck waits to see whether a slide follows.
        var heldDown: HeldEvent?
        /// Counts gestures. Outputs reach the main actor later, so each carries the count it was
        /// produced under: a queued output from an earlier gesture can then be told apart.
        var gesture = 0

        mutating func stamp(_ outputs: [RecognizerOutput]) -> [Stamped] {
            outputs.map { output in
                if case .gestureBegan = output { gesture += 1 }
                return Stamped(output: output, gesture: gesture)
            }
        }

        /// The held mouse-down, once the recognizer no longer holds it: it is to be posted now.
        mutating func takeReleasedHeldDown() -> HeldEvent? {
            guard let down = heldDown, !recognizer.isHolding else { return nil }
            heldDown = nil
            return down
        }
    }
    @ObservationIgnored nonisolated private let shared: Locked<Shared>

    // Main actor only; not observed (views only read `state` and `brightnessAvailable`).
    @ObservationIgnored private var settings: HalodeckSettings
    @ObservationIgnored private var gestureDevice: Int?
    @ObservationIgnored private var gestureSide: Side?
    @ObservationIgnored private var gestureNet = 0
    /// The end this slide last bumped against (true = 100%), nil when it hasn't or has since
    /// stepped the other way: pushing on at an end bumps once, not on every step.
    @ObservationIgnored private var gestureBumped: Bool?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var levels = LevelTracker()
    @ObservationIgnored private var cornerClicks = CornerClickCounter()
    /// What the sound-off sign was last told; nil until the first update.
    @ObservationIgnored private var soundSilent: Bool?

    /// `live: false` builds an inert engine (no settings sink, no system observers) for UI snapshots
    /// and tests; it only does what it is told through its methods.
    init(store: SettingsStore, services: EngineServices, live: Bool = true) {
        self.services = services
        self.pointer = services.pointer
        self.settings = store.settings
        let brightness = services.levels.brightnessAvailable
        self.brightnessAvailable = brightness
        services.hud.configure(showInNotch: store.settings.showInNotch, effect: store.settings.notchEffect,
                               muteSigns: store.settings.muteSignsSide)
        self.shared = Locked(Shared(recognizer: Recognizer(
            config: Engine.makeConfig(store.settings, brightnessAvailable: brightness))))
        guard live else { return }
        observers.observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { [weak self] in
            guard let self else { return }
            self.execute(self.shared.withLock { $0.stamp($0.recognizer.reset()) })
        }
        observers.observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screensChanged()
        }
        settingsSink = store.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in MainActor.assumeIsolated { self?.apply(new) } }
        services.accessibility.watch { [weak self] in self?.checkPermission() }
        // The sound-off sign by the notch follows the output's mute switch and volume (muted or at 0%),
        // wherever they are changed; read once now, so a sound off before launch shows its sign too.
        services.levels.watchOutput { [weak self] in self?.outputChanged() }
        outputChanged()
    }

    private func outputChanged() {
        let levelControl = services.levels
        setSoundSilent(SpeakerSymbol.isSilent(level: levelControl.volume(), muted: levelControl.isMuted))
    }

    /// Tells the HUD only when the sign changes (a slide's own update and CoreAudio's report after it agree).
    private func setSoundSilent(_ silent: Bool) {
        guard silent != soundSilent else { return }
        soundSilent = silent
        services.hud.setSoundSilent(silent)
    }

    nonisolated static func makeConfig(_ s: HalodeckSettings, brightnessAvailable: Bool) -> RecognizerConfig {
        var sides: [Side: SideAction] = [:]
        for (side, function) in s.activeSides {
            if function == .brightness && !brightnessAvailable { continue }
            sides[side] = function
        }
        let corners = s.activeCorners
        return RecognizerConfig(swipeSides: Set(s.swipeWithoutClick.filter(\.value).keys),
                                layout: ZoneLayout(sideWidthFraction: s.sideWidthFraction),
                                slidePerStepMM: s.slidePerStepMM,
                                activeSides: sides, activeCorners: corners)
    }

    func apply(_ new: HalodeckSettings) {
        let old = settings
        settings = new
        if new.enabled != old.enabled && new.showInNotch { services.hud.greet(on: new.enabled) }
        services.hud.configure(showInNotch: new.showInNotch, effect: new.notchEffect, muteSigns: new.muteSignsSide)
        updateConfig()
        setEnabled(new.enabled)
    }

    private func updateConfig() {
        let config = Engine.makeConfig(settings, brightnessAvailable: brightnessAvailable)
        execute(shared.withLock { $0.stamp($0.recognizer.update(config: config)) })
    }

    /// Displays came or went (lid closed, external screen): brightness may have become (un)available,
    /// and the notch, the pill's place and the mic sign may have moved.
    func screensChanged() {
        services.levels.refreshDisplays()
        let available = services.levels.brightnessAvailable
        if available != brightnessAvailable {
            brightnessAvailable = available
            updateConfig()
        }
        services.hud.screensChanged()
    }

    func setEnabled(_ on: Bool) {
        if on {
            guard state == .off || state == .needsAccessibility || state == .noTrackpad else { return }
            if !services.accessibility.isGranted || !startTap() {
                stopActive()
                setState(.needsAccessibility)
                return
            }
            shared.withLock { $0.active = true }
            services.touches.start(
                onFrame: { [weak self] frame in self?.handleFrame(frame) },
                onDevicesChanged: { [weak self] refs in self?.devicesChanged(refs) })
            refreshState()
        } else {
            stopActive()
            setState(.off)
        }
    }

    private func startTap() -> Bool {
        services.tap.start(
            handler: { [weak self] type, event, post in self?.handleEvent(type, event, post: post) ?? true },
            onDisabled: { [weak self] in self?.tapWasDisabled() })
    }

    private func devicesChanged(_ refs: [Int: MTDeviceRef]) {
        services.feedback.prepare(devices: refs)
        // Trackpads were re-created: anything tied to the old ones must end now.
        execute(shared.withLock { $0.stamp($0.recognizer.forgetDevices(notIn: Set(refs.keys))) })
        refreshState()
    }

    private func stopActive() {
        execute(shared.withLock { s in
            s.active = false
            return s.stamp(s.recognizer.reset())
        })
        flushHeldDown()
        pointer.unfreeze()
        services.tap.stop()
        services.touches.stop()
        stopTicker()
    }

    /// Event-tap thread. While the tap was disabled, the rest of a held click went straight to the
    /// app; posting the held mouse-down now would leave the button stuck, so drop it and wind
    /// everything down.
    nonisolated private func tapWasDisabled() {
        let outputs = shared.withLock { s in
            s.heldDown = nil
            return s.stamp(s.recognizer.reset())
        }
        pointer.unfreeze()
        onMain(outputs)
    }

    private func refreshState() {
        guard shared.withLock({ $0.active }) else { return }
        setState(services.touches.hasDevices ? .running : .noTrackpad)
    }

    private func setState(_ new: EngineState) {
        guard state != new else { return }
        state = new
        log.notice("engine state \(String(describing: new), privacy: .public)")
    }

    private func checkPermission() {
        let granted = services.accessibility.isGranted
        if state == .needsAccessibility, granted, settings.enabled {
            setState(.off)
            setEnabled(true)
        } else if (state == .running || state == .noTrackpad), !granted {
            stopActive()
            setState(.needsAccessibility)
        }
    }

    nonisolated private func onMain(_ outputs: [Stamped]) {
        guard !outputs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.execute(outputs) }
        }
    }

    // MARK: - Touches (multitouch thread)

    nonisolated func handleFrame(_ frame: TouchFrame) {
        let ids = Set(frame.touches.map(\.id))
        // The pointer position is only needed when a finger lands; reading it is a WindowServer
        // round trip, so do it outside the lock, only then, and never while Halodeck is off.
        let landing: Bool? = shared.withLock { s in
            guard s.active else { return nil }
            return !ids.subtracting(s.knownFingers[frame.device] ?? []).isEmpty
        }
        guard let landing else { return }
        let cursor = landing ? pointer.location() : nil
        let outputs: [Stamped] = shared.withLock { s in
            guard s.active else { return [] }
            let fresh = ids.subtracting(s.knownFingers[frame.device] ?? [])
            if !fresh.isEmpty, let cursor {
                for id in fresh { s.landingCursor[frame.device, default: [:]][id] = cursor }
            }
            s.knownFingers[frame.device] = ids
            s.landingCursor[frame.device] = s.landingCursor[frame.device]?.filter { ids.contains($0.key) }
            return s.stamp(s.recognizer.touchFrame(frame))
        }
        onMain(outputs)
    }

    // MARK: - Mouse events (event-tap thread)

    /// True = let the event through, false = swallow it. `post` sends an event ahead of this one.
    nonisolated func handleEvent(_ type: CGEventType, _ event: CGEvent, post: (CGEvent) -> Void) -> Bool {
        switch type {
        case .leftMouseDown:
            let (flushed, decision) = shared.withLock { s in
                let flushed = s.takeReleasedHeldDown()
                let decision = s.recognizer.mouseDown()
                if decision == .hold { s.heldDown = event.copy().map(HeldEvent.init) }
                return (flushed, decision)
            }
            if let flushed { send(flushed.event, post) }
            return decision == .pass

        case .leftMouseDragged, .mouseMoved:
            let (swallow, flushed) = shared.withLock { s in
                let swallow = type == .leftMouseDragged ? s.recognizer.mouseDragged() : s.recognizer.isGestureActive
                return (swallow, swallow ? nil : s.takeReleasedHeldDown())
            }
            if swallow {
                pointer.pin(event.location)
                return false
            }
            if let flushed { send(flushed.event, post) }
            return true

        case .leftMouseUp:
            enum Up { case replay(HeldEvent), done(swallow: Bool, rest: [Stamped], flushed: HeldEvent?) }
            let up: Up = shared.withLock { s in
                let (swallow, outputs) = s.recognizer.mouseUp()
                if outputs.contains(.replayHeldClick), let down = s.heldDown {
                    s.heldDown = nil
                    return .replay(down)
                }
                let rest = s.stamp(outputs.filter { $0 != .replayHeldClick })
                // A swallowed mouse-up ends the click: a held mouse-down (corner action, cancelled
                // corner click) must be dropped here, or the next click would post it to the app first.
                if swallow {
                    s.heldDown = nil
                    return .done(swallow: true, rest: rest, flushed: nil)
                }
                return .done(swallow: false, rest: rest, flushed: s.takeReleasedHeldDown())
            }
            switch up {
            case let .replay(down):
                let up = event.copy()
                up?.location = down.event.location
                send(down.event, post)
                if let up { send(up, post) }
                return false
            case let .done(swallow, rest, flushed):
                // Corner actions can block (opening apps): they run on the main actor, not here.
                onMain(rest)
                if let flushed { send(flushed.event, post) }
                return !swallow
            }

        default:
            return true
        }
    }

    nonisolated private func send(_ event: CGEvent, _ post: (CGEvent) -> Void) {
        event.tagAsHalodeck()
        post(event)
    }

    // MARK: - Carrying out decisions (main actor)

    private func execute(_ outputs: [Stamped]) {
        for item in outputs {
            switch item.output {
            case let .gestureBegan(side, _, device, finger):
                // Outputs reach the main actor asynchronously: skip a start that a reset already undid.
                guard isCurrent(item) else { continue }
                gestureDevice = device
                gestureSide = side
                gestureNet = 0
                gestureBumped = nil
                // A gesture that grew out of a held click freezes where the click was; the click is dropped.
                let home = shared.withLock { s in
                    defer { s.heldDown = nil }
                    return s.heldDown?.event.location ?? s.landingCursor[device]?[finger]
                } ?? pointer.location() ?? .zero
                pointer.freeze(at: home)
                startTicker()
            case let .steps(function, count):
                guard isCurrent(item) else { continue }
                step(function, count)
            case .gestureEnded:
                gestureDevice = nil
                gestureSide = nil
                gestureBumped = nil
                pointer.unfreeze()
            case let .cornerAction(corner):
                // Count quick repeated clicks; a corner with only a 1-click action fires at once.
                if let done = cornerClicks.click(corner, at: services.input.now, maxClicks: settings.maxClicks(corner),
                                                 interval: services.input.doubleClickInterval) {
                    runCorner(done)
                }
                if cornerClicks.isWaiting { startTicker() }
            case .replayHeldClick:
                break   // handled in handleEvent, where the mouse-up event is at hand
            case .releaseHeldDown:
                flushHeldDown()
            }
        }
    }

    /// The output belongs to the gesture running now (not to one a reset ended, nor to an earlier one).
    private func isCurrent(_ item: Stamped) -> Bool {
        shared.withLock { $0.active && $0.recognizer.isGestureActive && $0.gesture == item.gesture }
    }

    private func step(_ function: SideAction, _ count: Int) {
        let input = services.input
        // Option for quarter steps, Shift for eighths (level sides only; fine wins when both are held).
        let mode = LevelStep.chosen(isLevel: function.isLevel,
                                    fine: settings.fineControlKey == .option && input.isOptionHeld,
                                    coarse: settings.coarseControlKey == .shift && input.isShiftHeld)
        // The level before this step, read at most once (each read is a system call).
        var current: Double??
        let read = { () -> Double? in
            if let current { return current }
            let level = self.level(of: function)
            current = .some(level)
            return level
        }
        // The level after each step that still changes something; steps at 0% / 100% stay silent.
        // An unknown level gives a tick for every step, so fewer ticks than steps means a known
        // level ran into 0% or 100%: then the notch bumps at that end, once per push (again only
        // after a step the other way, or in the next gesture).
        let steps = levels.steps(for: count, step: mode, function: function, now: input.now, read: read)
        let tickLevels = steps.tickLevels
        let up = count > 0

        setDirectly(function, to: { mode.level(from: $0, steps: count) }, up: count >= 0, from: read)
        indicate(function, count)
        if gestureBumped != up { gestureBumped = nil }
        if function.isLevel && tickLevels.count < abs(count) && gestureBumped == nil {
            gestureBumped = up
            services.hud.bump(atTop: up)
        }
        // Media keys move a sixteenth (a quarter step with fine's Shift+Option): a coarse step
        // presses as many as reach the next eighth from the predicted level.
        var keyLevel = steps.start
        for i in 0..<abs(count) {
            for _ in 0..<mode.keyPresses(from: keyLevel, up: up) { perform(function, up: up, fine: mode == .fine) }
            keyLevel = keyLevel.map { mode.next(from: $0, up: up) }
            guard i < tickLevels.count, settings.ticksEnabled[gestureSide ?? .left] ?? true else { continue }
            if settings.hapticsEnabled, let device = gestureDevice {
                services.feedback.tick(device: device, id: settings.hapticTick)
            }
            if settings.soundEnabled {
                services.feedback.play(settings.soundStyle, level: tickLevels[i])
            }
        }
    }

    /// nil when the level is unknown or the function has none.
    private func level(of function: SideAction) -> Double? {
        let levelControl = services.levels
        switch function {
        case .volume: return levelControl.volume()
        case .brightness: return levelControl.brightness()
        case .keyboardBacklight where levelControl.keyboardLightAvailable: return levelControl.keyboardLight()
        default: return nil   // no level to read: every step ticks
        }
    }

    /// With the indicator in the notch, Halodeck sets volume itself (no key press, so no system
    /// indicator) and shows the level in the notch. Not for outputs without a volume control.
    private var volumeDirect: Bool { services.hud.showsInNotch && services.levels.canSetVolume }
    private var brightnessDirectNow: Bool {
        (settings.brightnessDirect || services.hud.showsInNotch) && brightnessAvailable
    }

    /// Levels set directly rather than with keys: exact steps, but macOS shows no indicator, so
    /// Halodeck shows the new level. `read` gives the level before the step; `target` turns it into
    /// the level after it.
    private func setDirectly(_ function: SideAction, to target: (Double) -> Double, up: Bool,
                             from read: () -> Double?) {
        let levelControl = services.levels
        switch function {
        case .volume where volumeDirect:
            guard let current = read() else { return }
            let level = target(current)
            levelControl.setVolume(level)
            // Turning the volume up unmutes; at 0% the mute switch is as it was.
            let muted = level > 0.001 ? false : levelControl.isMuted ?? false
            services.hud.show(symbol: SpeakerSymbol.name(level: level, muted: muted), level: level, up: up)
            // The level just set decides the sound-off sign now, ahead of CoreAudio's report.
            setSoundSilent(SpeakerSymbol.isSilent(level: level, muted: muted))
        case .brightness where brightnessDirectNow:
            guard let current = read() else { return }
            let level = target(current)
            levelControl.setBrightness(level)
            services.hud.show(symbol: "sun.max.fill", level: level, up: up)
        case .keyboardBacklight where levelControl.keyboardLightAvailable:
            guard let current = read() else { return }
            let level = target(current)
            levelControl.setKeyboardLight(level)
            services.hud.show(symbol: "light.max", level: level, up: up)
        default:
            break
        }
    }

    private func indicate(_ function: SideAction, _ count: Int) {
        guard settings.showIndicator else { return }
        let hud = services.hud
        let up = count >= 0
        switch function {
        case .switchTab:
            gestureNet += count
            hud.show(symbol: "square.on.square", text: label(gestureNet, "Next tab", "Previous tab"), up: up)
        case .mediaSeek:
            gestureNet += count
            hud.show(symbol: gestureNet >= 0 ? "goforward" : "gobackward", text: label(gestureNet, "Forward", "Back"), up: up)
        case .track:
            gestureNet += count
            hud.show(symbol: gestureNet >= 0 ? "forward.end.fill" : "backward.end.fill",
                     text: label(gestureNet, "Next track", "Previous track"), up: up)
        case .customKeys:
            gestureNet += count
            let combo = gestureSide.flatMap { settings.customKey($0, up: gestureNet >= 0) }
            let name = combo?.displayString ?? "No shortcut"
            hud.show(symbol: "keyboard", text: label(gestureNet, name, name), up: up)
        case .volume, .brightness, .keyboardBacklight, .nothing:
            break   // macOS's own indicator, or ours from `setDirectly` (or nothing to show)
        }
    }

    private func label(_ net: Int, _ forward: String, _ backward: String) -> String {
        guard net != 0 else { return "Back to start" }
        let name = net > 0 ? forward : backward
        return abs(net) > 1 ? "\(name) ×\(abs(net))" : name
    }

    /// `up` means up for the left and right sides and right for the top and bottom ones.
    private func perform(_ function: SideAction, up: Bool, fine: Bool) {
        let events = services.events
        switch function {
        case .volume:
            if !volumeDirect { events.press(up ? .volumeUp : .volumeDown, fine: fine) }
        case .brightness:
            if !brightnessDirectNow { events.press(up ? .brightnessUp : .brightnessDown, fine: fine) }
        case .keyboardBacklight:
            if !services.levels.keyboardLightAvailable { events.press(up ? .keyboardLightUp : .keyboardLightDown, fine: fine) }
        case .mediaSeek: events.post(keyCode: up ? KeyPress.rightArrow : KeyPress.leftArrow, flags: [])
        case .track: events.press(up ? .next : .previous, fine: false)
        case .switchTab:
            events.post(keyCode: KeyPress.tab, flags: up ? .maskControl : [.maskControl, .maskShift])
        case .customKeys:
            guard let side = gestureSide, let combo = settings.customKey(side, up: up) else { break }
            events.post(keyCode: combo.keyCode, flags: CGEventFlags(rawValue: combo.modifiers))
        case .nothing: break
        }
    }

    private func runCorner(_ click: CornerClick) {
        let hud = services.hud
        if hud.showsInNotch { hud.burst(corner: click.corner, clicks: click.count) }
        services.actions.run(settings.cornerAction(click.corner, clicks: click.count))
        if hud.showsInNotch { hud.hostBursts() }
    }

    /// Posts a held mouse-down that is being let through, from the main actor (outside the tap).
    private func flushHeldDown() {
        guard let down = shared.withLock({ $0.takeReleasedHeldDown() }) else { return }
        services.events.postToSession(down.event)
    }

    /// Runs every 50 ms while a gesture is running or corner clicks are being counted: ends gestures
    /// whose trackpad went silent, fires counted clicks, and tells the pointer watchdog the main
    /// thread is alive. Common run-loop modes, so it also runs during menus and panels.
    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// One beat of the ticker (internal so tests can beat it with a fake clock).
    func tick() {
        pointer.heartbeat()
        let now = services.input.now
        let (outputs, busy) = shared.withLock { s in
            (s.stamp(s.recognizer.tick(time: now)), s.recognizer.isGestureActive)
        }
        execute(outputs)
        while let done = cornerClicks.tick(now: now, interval: services.input.doubleClickInterval) {
            runCorner(done)
        }
        if !busy && !cornerClicks.isWaiting { stopTicker() }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
