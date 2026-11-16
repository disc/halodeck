import AppKit
import HalodeckCore

enum HUDContent: Equatable {
    case text(String)
    /// A 0...1 level: the segmented bar in the pill, a number (or bar) in the notch.
    case level(Double)
}

@MainActor
final class HUDController: HUDPresenting {
    private let pill = StatusHUD()
    private let notch = NotchHUD()
    private let greeting = NotchGreetingPresenter()
    private let muteEars = MuteEars()
    private let announcer = HUDAnnouncer()
    private let observers = ObserverBag()

    /// Settings → Advanced → Indicator → "Show in the notch".
    private var prefersNotch = true
    /// Settings → Advanced → Indicator → "Mute signs".
    private var muteSignsSide: MuteSignsSide = .right
    private var microphoneMuted = false
    /// The output is muted or at 0%.
    private var soundSilent = false

    init() {
        notch.onVisibilityChange = { [weak self] in self?.updateMuteEars() }
        greeting.onVisibilityChange = { [weak self] in self?.updateMuteEars() }
        readDisplayOptions()
        observers.observe(NSWorkspace.shared.notificationCenter,
                          NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.readDisplayOptions()
        }
    }

    /// True when the indicator will show in the notch (setting on, and the active screen has one).
    /// Then Halodeck also sets volume and brightness itself, so macOS draws no indicator of its own.
    var showsInNotch: Bool {
        prefersNotch && NSScreen.main.flatMap(NotchHUD.geometry(for:)) != nil
    }

    func configure(showInNotch: Bool, effect: NotchEffect, muteSigns: MuteSignsSide) {
        notch.model.effect = effect
        guard showInNotch != prefersNotch || muteSigns != muteSignsSide else { return }
        prefersNotch = showInNotch
        muteSignsSide = muteSigns
        updateMuteEars()
    }

    func greetAtLaunch() { greeting.greet(flipsIcon: true) }

    func greet(on: Bool) { greeting.greet(label: on ? "On" : "Off", reverse: !on) }

    func show(symbol: String, content: HUDContent, up: Bool) {
        present(symbol: symbol, content: content, image: nil, direction: up ? 1 : -1)
    }

    /// An app's own icon with a label (Open app) in the notch; the pill shows a generic app symbol.
    func show(appIcon: NSImage, text: String) {
        present(symbol: "app.fill", content: .text(text), image: appIcon, direction: 1)
    }

    func bump(atTop: Bool) { notch.bump(atTop: atTop) }

    func burst(corner: Corner, clicks: Int) {
        greeting.dismiss()
        notch.burst(left: corner.isLeft, top: corner.isTop, clicks: clicks)
    }

    func hostBursts() {
        greeting.dismiss()
        notch.hostBursts(on: NSScreen.main)
    }

    func setMicrophoneMuted(_ muted: Bool) {
        microphoneMuted = muted
        updateMuteEars()
    }

    func setSoundSilent(_ silent: Bool) {
        guard silent != soundSilent else { return }
        soundSilent = silent
        updateMuteEars()
    }

    /// Re-reads the microphone (at launch: one muted before Halodeck started shows its sign too).
    func refreshMicrophone() { setMicrophoneMuted(Microphone.isMuted ?? false) }

    func screensChanged() {
        notch.screensChanged(main: NSScreen.main)
        greeting.screensChanged()
        pill.screensChanged(main: NSScreen.main)
        updateMuteEars()
    }

    private func present(symbol: String, content: HUDContent, image: NSImage?, direction: Int) {
        // A launch or On/Off greeting still running gives way: one shape at the notch at a time.
        greeting.dismiss()
        if prefersNotch, let screen = NSScreen.main,
           notch.show(symbol: symbol, content: content, image: image, direction: direction, on: screen) {
            pill.hide()   // a pill still up from before the switch
        } else {
            pill.show(symbol: symbol, content: content)
        }
        announcer.announce(symbol: symbol, content: content)
    }

    /// The muted signs show beside the notch, except while the indicator or a greeting covers them (so
    /// the two shapes' edges never sit on top of each other).
    private func updateMuteEars() {
        let shown = prefersNotch && !(notch.isVisible || greeting.isShowing)
        muteEars.update(sound: shown && soundSilent, microphone: shown && microphoneMuted, side: muteSignsSide)
    }

    private func readDisplayOptions() {
        let workspace = NSWorkspace.shared
        let reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        notch.model.reduceMotion = reduceMotion
        greeting.reduceMotion = reduceMotion
        pill.reduceMotion = reduceMotion
        pill.reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
    }
}

/// The HUD panels never take focus or clicks, so VoiceOver can't read them: what they show is spoken
/// as an announcement instead. A fast slide changes the value many times a second, so only the latest
/// value is spoken, once the indicator has been quiet for a moment.
@MainActor
final class HUDAnnouncer {
    private static let quiet: Duration = .milliseconds(400)
    private var pending: Task<Void, Never>?

    func announce(symbol: String, content: HUDContent) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let text = Self.text(symbol: symbol, content: content)
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: Self.quiet)
            guard !Task.isCancelled else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text,
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    static func text(symbol: String, content: HUDContent) -> String {
        switch content {
        case let .text(text):
            return text
        case let .level(level):
            let percent = "\(Int((min(1, max(0, level)) * 100).rounded()))%"
            let name = symbol.hasPrefix("speaker") ? "Volume"
                : symbol.hasPrefix("sun") ? "Brightness"
                : symbol.hasPrefix("light") ? "Keyboard light" : nil
            return name.map { "\($0) \(percent)" } ?? percent
        }
    }
}

@MainActor
enum HUDPanel {
    /// `stationary` panels stay put during Mission Control and space switches; the others (the pill)
    /// are transient.
    static func make(level: NSWindow.Level, size: NSSize = .zero, stationary: Bool = true,
                     content: NSView? = nil) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    stationary ? .stationary : .transient, .ignoresCycle]
        if let content { panel.contentView = content }
        return panel
    }
}
