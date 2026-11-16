#if HALODECK_SNAPSHOT || DEBUG
import AppKit
import HalodeckCore
import SwiftUI

/// `Halodeck --snapshot <dir>` renders the panel, the Settings tabs and more to PNGs in light and dark mode,
/// then exits. Used to check the UI without clicking through it; never touches the trackpad.
/// Development builds only: debug builds, and `scripts/build-app.sh` without RELEASE=1 (which compiles
/// with HALODECK_SNAPSHOT); release builds leave it out.
@MainActor
enum DebugSnapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Settings in a scratch suite of their own, emptied before and after (one fixed name, so runs
        // don't leave a preferences file each behind).
        let suite = "halodeck.snapshot"
        guard let defaults = UserDefaults(suiteName: suite) else { return true }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let engine = Engine(store: store, services: .live(hud: HUDController()), live: false)

        for (name, view) in views(store: store, engine: engine) {
            for dark in [false, true] {
                render(view, to: dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"), dark: dark)
            }
        }
        for tab in SettingsTab.allCases where tab != .about {
            for dark in [false, true] {
                renderSettings(tab, store: store, engine: engine, dark: dark,
                               to: dir.appendingPathComponent("settings-\(tab.name)-\(dark ? "dark" : "light").png"))
            }
        }
        // About as a release build shows it (a development build has no feed and hides Updates): a copy
        // that updates itself with Sparkle, and one installed with Homebrew. Sparkle is never started.
        for channel in [UpdateChannel.sparkle, .homebrew] {
            let updates = UpdateService(isAvailable: true, channel: channel, makeUpdater: { _ in nil })
            updates.automaticallyChecks = true
            for dark in [false, true] {
                renderSettings(.about, store: store, engine: engine, updates: updates, dark: dark,
                               to: dir.appendingPathComponent("settings-about-\(channel)-\(dark ? "dark" : "light").png"))
            }
        }
        // A downloaded copy whose daily check found 0.1.1: About, the panel and the menu-bar icon.
        let waiting = UpdateService(isAvailable: true, channel: .sparkle, makeUpdater: { _ in nil })
        waiting.automaticallyChecks = true
        waiting.updateFound(version: "0.1.1")
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            renderSettings(.about, store: store, engine: engine, updates: waiting, dark: dark,
                           to: dir.appendingPathComponent("settings-about-update-\(mode).png"))
            render(AnyView(PanelView(store: store, engine: engine, updates: waiting) {}),
                   to: dir.appendingPathComponent("panel-update-\(mode).png"), dark: dark)
            render(AnyView(HStack(spacing: 18) {
                Image(nsImage: MenuBarIcon.image(on: true)).renderingMode(.template)
                Image(nsImage: MenuBarIcon.image(on: true, dot: true)).renderingMode(.template)
                Image(nsImage: MenuBarIcon.image(on: false, dot: true)).renderingMode(.template)
            }.padding(12)), to: dir.appendingPathComponent("menubar-icon-update-\(mode).png"), dark: dark)
        }
        store.settings.hapticsEnabled = false
        store.settings.soundEnabled = false
        renderSettings(.bindings, store: store, engine: engine, dark: false, maxPageHeight: 4000,
                       to: dir.appendingPathComponent("settings-bindings-nofeedback-light.png"))
        return true
    }

    static func views(store: SettingsStore, engine: Engine) -> [(String, AnyView)] {
        [("panel", AnyView(PanelView(store: store, engine: engine) {})),
         ("map-states", zoneStates(store: store)),
         ("menubar-icon", AnyView(HStack(spacing: 24) {
             ForEach([true, false], id: \.self) { on in
                 Image(nsImage: MenuBarIcon.image(on: on)).resizable().renderingMode(.template)
                     .frame(width: 80, height: 64).foregroundStyle(.primary)
             }
         }.padding(20))),
         ("hud", AnyView(VStack(spacing: 0) {
             HUDPill(symbol: "mic.slash.fill", content: .text("Microphone off"))
             HUDPill(symbol: "sun.max.fill", content: .level(0.9))
             HUDPill(symbol: "speaker.wave.2.fill", content: .level(0.4), background: .opaque)   // Reduce Transparency
         }.padding(10).background(LinearGradient(colors: [.indigo, .teal], startPoint: .leading, endPoint: .trailing)))),
         ("notch", notchStates()),
         ("notch-glow", notchGlowFrames()),
         ("notch-extras", notchExtras())]
    }

    private static func render(_ view: AnyView, to url: URL, dark: Bool) {
        let host = NSHostingView(rootView: AnyView(view
            .background(dark ? Color(white: 0.17) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.95, alpha: 1)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The real Settings window on `tab`, toolbar and title bar included: its frame view drawn into an
    /// image (no screen capture, so no Screen Recording permission). Never shown on screen.
    private static func renderSettings(_ tab: SettingsTab, store: SettingsStore, engine: Engine,
                                       updates: UpdateService = .shared, dark: Bool,
                                       maxPageHeight: CGFloat = Metrics.settingsMaxPageHeight, to url: URL) {
        let controller = SettingsWindowController(store: store, engine: engine, updates: updates)
        let window = controller.prepareWindow(tab: tab, maxPageHeight: maxPageHeight, fitsScreen: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        for _ in 0..<3 {   // let SwiftUI measure the page and the window follow its height
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}

private extension SettingsTab {
    var name: String { title.lowercased() }
}

extension DebugSnapshot {
    static func zoneStates(store: SettingsStore) -> AnyView {
        var s = store.settings
        s.corners[.topRight] = .muteMicrophone
        s.sides[.left] = .volume
        s.sides[.right] = .brightness
        s.sides[.top] = .nothing
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 28) {
                TrackpadMapView(settings: s, brightnessAvailable: false, size: .large).frame(width: 420, height: 250)
                TrackpadMapView(settings: s, brightnessAvailable: false, size: .compact).frame(width: 288, height: 172)
            }
            Text("Left: active (Volume) · Right: unavailable (Brightness, no built-in display) · Top: unset (Nothing) · Bottom: active (Media seek)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24))
    }

    static func notchStates() -> AnyView {
        // (seconds since it opened, or nil = closed; symbol; content; light)
        let states: [(Double?, String, HUDContent, NotchEffect)] = [
            (nil, "speaker.wave.2.fill", .level(0.5), .off),
            (5, "speaker.wave.2.fill", .level(0.62), .off),
            (5, "square.on.square", .text("Next tab ×2"), .off),
            (5, "mic.slash.fill", .text("Microphone off"), .off),
            (5, "app.fill", .text("Safari"), .off),
            (5, "square.on.square", .text("Next tab ×3"), .everyStep),
            (5, "sun.max.fill", .level(0.3), .levelGauge),
            (5, "speaker.wave.3.fill", .level(0.85), .levelGauge),
        ]
        let now = Date()
        return AnyView(VStack(spacing: 6) {
            ForEach(states.indices, id: \.self) { i in
                let (age, symbol, content, effect) = states[i]
                indicator(symbol, content, effect: effect, openedAgo: age, at: now) { model in
                    if case .text("Safari") = content { model.image = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app") }
                    if effect == .everyStep {   // two steps in a row: both streaks still running
                        model.streaks.add(at: now.addingTimeInterval(-0.3), direction: 1)
                        model.streaks.add(at: now.addingTimeInterval(-0.12), direction: 1)
                    }
                }
            }
        }.padding(20).background(Color(white: 0.75)))
    }

    /// The notch indicator at `now`, `age` s after it opened (nil: closed), over the fake menu bar.
    private static func indicator(_ symbol: String, _ content: HUDContent, effect: NotchEffect = .off,
                                  openedAgo age: Double? = 5, at now: Date,
                                  _ setup: (NotchModel) -> Void = { _ in }) -> some View {
        let model = NotchModel()
        model.symbol = symbol; model.content = content; model.effect = effect
        let ear = NotchHUD.earWidth(for: content, levelAsNumber: model.levelAsNumber)
        model.earFrom = ear; model.earTo = ear
        if case .level(let v) = content { model.gauge.jump(to: v) }
        model.openedAt = age.map { now.addingTimeInterval(-$0) } ?? .distantFuture
        setup(model)
        return NotchIndicator(model: model, date: now).background(alignment: .top) { menuBar }
    }

    private static var menuBar: some View {
        Color(white: 0.93).frame(height: Metrics.defaultNotch.height)
            .overlay(alignment: .top) {
                NotchShape().fill(.black)
                    .frame(width: Metrics.defaultNotch.width + 2 * NotchGeometry.shoulder, height: Metrics.defaultNotch.height)
            }
    }

    static func notchGlowFrames() -> AnyView {
        let notch = Metrics.defaultNotch, m = NotchHUD.glowMargin
        let ear = NotchHUD.earWidth(for: .text(NotchGreeting.name), levelAsNumber: true)
        func row(_ greeting: some View) -> some View {
            ZStack(alignment: .top) {
                Color(white: 0.93).frame(height: notch.height)
                NotchShape().fill(.black).frame(width: notch.width + 2 * NotchGeometry.shoulder, height: notch.height)
                greeting
            }
            .frame(width: 520, height: notch.height + m, alignment: .top)
            .background(Color(white: 0.85))
        }
        return AnyView(VStack(spacing: 14) {
            ForEach([0.2, 0.7, 1.2, 1.7, 2.45], id: \.self) { t in
                row(NotchGreeting(notch: notch, ear: ear, margin: m, time: t))
            }
            // Switching off: the menu bar's "off" glyph, the light running back and draining to grey.
            row(NotchGreeting(notch: notch, ear: NotchHUD.earWidth(for: .text("Off"), levelAsNumber: true), margin: m,
                              label: "Off", reverse: true).time(1.2))
        }.padding(20))
    }

    static func notchExtras() -> AnyView {
        let now = Date()
        let notch = Metrics.defaultNotch
        // The level gauge (the shipping light) at the end the slide ran into, `t` s into its bump (no
        // light at 0%: the push alone).
        func bump(top: Bool, _ t: Double) -> some View {
            indicator(top ? "speaker.wave.3.fill" : "speaker.fill", .level(top ? 1 : 0), effect: .levelGauge, at: now) {
                $0.bump = NotchBump(at: now.addingTimeInterval(-t), top: top)
            }
        }
        return AnyView(VStack(spacing: 6) {
            indicator("mic.slash.fill", .text("Microphone off"), at: now) {
                $0.bursts.add(left: true, top: true, clicks: 1, at: now.addingTimeInterval(-0.22))
                $0.bursts.add(left: false, top: false, clicks: 1, at: now.addingTimeInterval(-0.22))
            }
            ForEach([0.06, 0.15, 0.3], id: \.self) { bump(top: true, $0) }
            ForEach([0.06, 0.15, 0.3], id: \.self) { bump(top: false, $0) }
            muteEars(.right, sound: false, microphone: true)
            muteEars(.right, sound: true, microphone: false)
            muteEars(.right, sound: true, microphone: true)
            muteEars(.left, sound: true, microphone: true)
            ZStack(alignment: .top) {
                menuBar.frame(width: 520)
                NotchGreeting(notch: notch, ear: NotchHUD.earWidth(for: .text("Off"), levelAsNumber: true),
                              margin: NotchHUD.glowMargin, label: "Off", reverse: true).time(0.75)
            }
            .frame(width: 520, height: 48, alignment: .top)
        }.padding(20).background(Color(white: 0.75)))
    }

    /// The muted signs over a fake menu bar, placed on its notch as `MuteEars` places its panel.
    private static func muteEars(_ side: MuteSignsSide, sound: Bool, microphone: Bool) -> some View {
        let notch = Metrics.defaultNotch
        let view = MuteEarsView(notchWidth: notch.width, notchHeight: notch.height,
                                layout: side.layout(sound: sound, microphone: microphone))
        return ZStack(alignment: .topLeading) {
            menuBar.frame(width: 520)
            view.frame(width: view.width, height: notch.height)
                .offset(x: 260 - notch.width / 2 - NotchGeometry.shoulder - view.leftEar)
        }
        .frame(width: 520, height: 34, alignment: .topLeading)
    }
}
#endif
