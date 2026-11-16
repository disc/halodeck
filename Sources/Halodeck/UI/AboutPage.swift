import AppKit
import HalodeckCore
import SwiftUI

struct AboutPage: View {
    @Bindable var updates: UpdateService

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            Text("Halodeck").font(.system(size: 26, weight: .bold))
            Text("Use the sides of your trackpad as sliders and its corners as buttons.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            if !updates.isAvailable {   // a release build shows its version under Updates
                Text("Version \(version)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .settingsCard()

        SectionHeader(title: "How it works")
        HStack(alignment: .top, spacing: 12) {
            tile(symbol: "hand.draw", title: "Sides",
                 text: "Press near a side and slide to change the volume, brightness or keyboard light, seek, skip tracks, switch tabs or press your own shortcuts.")
            tile(symbol: "square.dashed", title: "Corners",
                 text: "Click a corner to mute the sound or the microphone, press a shortcut, open an app or a link, or run a Shortcut.")
            tile(symbol: "waveform", title: "Feedback",
                 text: "A light tap, and a sound if you like, at every step. Both stop at 0% and 100%.")
        }
        .fixedSize(horizontal: false, vertical: true)   // all tiles as tall as the tallest
        Text("The rest of the trackpad works as before, and a plain click near a side is still an ordinary click.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)

        if updates.isAvailable {
            SectionHeader(title: "Updates")
            SettingsBox {
                switch updates.channel {
                case .sparkle:
                    SettingsRow(title: "Check for updates automatically",
                                subtitle: "Halodeck looks for new versions on GitHub and asks before installing one") {
                        Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks).labelsHidden()
                    }
                    if let available = updates.availableVersion {
                        SettingsRow(title: "Version \(available) is available", subtitle: "You have \(version)") {
                            Button("Update…") { updates.checkForUpdates() }
                        }
                    } else {
                        SettingsRow(title: "Version \(version)") {
                            Button("Check Now") { updates.checkForUpdates() }
                        }
                    }
                case .homebrew:
                    SettingsRow(title: "Version \(version)",
                                subtitle: "This copy was installed with Homebrew; update it with brew upgrade") {
                        Button("Update with Homebrew…") { updates.updateWithHomebrew() }
                            .help("Opens Terminal and runs: \(Homebrew.upgradeCommand)")
                    }
                }
            }
        }

        Label("Apple silicon · macOS 14+", systemImage: "laptopcomputer")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.top, 4)
    }

    private func tile(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.12)))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .settingsCard()
    }
}
