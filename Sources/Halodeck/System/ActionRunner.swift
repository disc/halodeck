import AppKit
import HalodeckCore
import os

@MainActor
struct ActionRunner: CornerActionRunning {
    nonisolated private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "actions")
    let levels: any LevelControl
    let hud: any HUDPresenting

    func run(_ action: CornerAction) {
        switch action {
        case .nothing:
            break
        case .mute:
            if hud.showsInNotch, let muted = levels.isMuted {
                levels.setMuted(!muted)
                hud.show(symbol: !muted ? "speaker.slash.fill" : SpeakerSymbol.name(level: levels.volume() ?? 0.5, muted: false),
                               text: !muted ? "Sound off" : "Sound on")
            } else {
                MediaKeys.press(.mute, fine: false)
            }
        case .muteMicrophone:
            if let muted = Microphone.toggleMute() {
                hud.setMicrophoneMuted(muted)
                hud.show(symbol: muted ? "mic.slash.fill" : "mic.fill",
                               text: muted ? "Microphone off" : "Microphone on")
            } else {
                hud.show(symbol: "mic.badge.xmark", text: "Can't mute this microphone")
            }
        case let .keyCombo(combo):
            KeyPress.post(keyCode: combo.keyCode, flags: CGEventFlags(rawValue: combo.modifiers))
            notch(action, combo.displayString)
        case let .openApp(path):
            if hud.showsInNotch {
                hud.show(appIcon: NSWorkspace.shared.icon(forFile: path), text: FileManager.default.displayName(atPath: path))
            }
            Self.openOrHide(URL(fileURLWithPath: path))
        case let .openLink(text):
            // Only http, https and mailto: never a local file or another app's scheme.
            guard let url = OpenLink.url(text) else {
                Self.log.error("refused link \(text, privacy: .private)")
                return
            }
            if !NSWorkspace.shared.open(url) { Self.log.error("couldn't open link \(url, privacy: .private)") }
            notch(action, url.host ?? text)
        case let .runShortcut(name):
            notch(action, name)
            Self.runShortcut(name)
        case .lockScreen:
            SystemUI.lockScreen()
        case .missionControl:
            notch(action, "Mission Control")
            SystemUI.missionControl()
        case .appExpose:
            notch(action, "App windows")
            SystemUI.appExpose()
        case .showDesktop:
            notch(action, "Show desktop")
            SystemUI.showDesktop()
        case .showApps:
            notch(action, "Apps")
            SystemUI.showApps()
        }
    }

    /// In the notch, a corner action shows its icon and name as it runs (the pill doesn't, to stay quiet).
    private func notch(_ action: CornerAction, _ text: String) {
        guard hud.showsInNotch else { return }
        hud.show(symbol: Theme.symbol(for: action), text: text)
    }

    /// `shortcuts run -- <name>`: the `--` keeps a name starting with "-" from being read as an option.
    nonisolated static func shortcutArguments(_ name: String) -> [String] { ["run", "--", name] }

    private static func runShortcut(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = shortcutArguments(name)
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            log.error("shortcut \(name, privacy: .private) exited with \(process.terminationStatus, privacy: .public)")
        }
        do {
            try process.run()
        } catch {
            log.error("shortcut \(name, privacy: .private) didn't start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func openOrHide(_ url: URL) {
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleURL?.standardizedFileURL == url.standardizedFileURL {
            front.hide()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                log.error("opening \(url.path, privacy: .private) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
