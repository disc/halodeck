import AppKit
import HalodeckCore
import SwiftUI

enum Theme {
    /// The single accent for switches, chips, checkboxes, pickers and sliders: the system blue (fixed,
    /// not the user's accent colour).
    static let accent = Color(nsColor: .systemBlue)
    static let glow = Color(nsColor: .systemBlue)
    static let trackpad = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.69, green: 0.70, blue: 0.72, alpha: 1)
            : NSColor(red: 0.47, green: 0.48, blue: 0.50, alpha: 1)
    })
    static let teal = Color(red: 0x5E / 255, green: 0xC8 / 255, blue: 0xB5 / 255)

    static let notchLightTealRGB = (red: 0.37, green: 0.89, blue: 0.76)
    static let notchLightBlueRGB = (red: 0.29, green: 0.56, blue: 0.95)
    static let notchLightTeal = Color(red: notchLightTealRGB.red, green: notchLightTealRGB.green, blue: notchLightTealRGB.blue)
    static let notchLightBlue = Color(red: notchLightBlueRGB.red, green: notchLightBlueRGB.green, blue: notchLightBlueRGB.blue)

    static func symbol(for action: CornerAction) -> String {
        switch action {
        case .nothing: "plus"
        case .mute: "speaker.slash.fill"
        case .muteMicrophone: "mic.slash.fill"
        case .keyCombo: "command"
        case .openApp: "app.fill"
        case .openLink: "link"
        case .runShortcut: "square.stack.3d.up.fill"
        case .lockScreen: "lock.fill"
        case .missionControl: "rectangle.3.group"
        case .appExpose: "uiwindow.split.2x1"
        case .showDesktop: "menubar.dock.rectangle"
        case .showApps: "square.grid.3x3.fill"
        }
    }
}

enum Metrics {
    /// The Settings window's fixed content width (the sides and corners tables need all of it), and
    /// the tallest a tab grows before its content scrolls.
    static let settingsWidth: CGFloat = 720
    static let settingsMaxPageHeight: CGFloat = 960

    /// A 14"/16" MacBook Pro notch: the notch model's starting size, and the snapshots' fake notch.
    static let defaultNotch = CGSize(width: 185, height: 33.5)
    /// Inset of the icon and the value from the outer ends of the notch indicator's ears.
    static let notchEarInset: CGFloat = 14
    /// Inset of the app icon from the left end of the launch greeting (its label keeps `notchEarInset`).
    static let greetingIconInset: CGFloat = 12
}

enum Easing {
    /// Ease in and out (quadratic), 0...1 to 0...1.
    static func inOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

extension SideAction {
    var symbol: String {
        switch self {
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .keyboardBacklight: "light.max"
        case .mediaSeek: "goforward"
        case .track: "forward.end.fill"
        case .switchTab: "square.on.square"
        case .customKeys: "keyboard"
        case .nothing: "minus"
        }
    }

    var title: String {
        switch self {
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .keyboardBacklight: "Keyboard light"
        case .mediaSeek: "Media seek"
        case .track: "Previous / next track"
        case .switchTab: "Switch tab"
        case .customKeys: "Custom keys"
        case .nothing: "Nothing"
        }
    }
}
