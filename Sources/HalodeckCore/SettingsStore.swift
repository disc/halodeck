import Combine
import Foundation
import os

/// Holds the current settings and saves them (sanitised, as JSON) to UserDefaults on every change.
/// Lives on the main actor: SwiftUI observes it and the app mutates it from the UI.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let key = "halodeck.settings"
    /// Saved settings that could not be read, kept here so a later save does not destroy them.
    public static let unreadableKey = "halodeck.settings.unreadable"
    private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "settings")
    private let defaults: UserDefaults

    @Published public var settings: HalodeckSettings {
        didSet { save() }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.load(from: defaults)
    }

    /// The saved settings; defaults when there are none or they can't be read (then the saved value
    /// is copied to `unreadableKey` first, since the next save replaces it).
    private static func load(from defaults: UserDefaults) -> HalodeckSettings {
        guard let stored = defaults.object(forKey: key) else { return HalodeckSettings() }
        if let data = stored as? Data,
           let decoded = try? JSONDecoder().decode(HalodeckSettings.self, from: data) {
            return decoded.sanitized()
        }
        defaults.set(stored, forKey: unreadableKey)
        log.error("Saved settings are unreadable: kept them under \(unreadableKey, privacy: .public) and started from defaults")
        return HalodeckSettings()
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(settings.sanitized()), forKey: Self.key)
        } catch {
            // The error's description can quote setting values, so only its kind is logged.
            Self.log.error("Couldn't encode settings, not saved: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}
