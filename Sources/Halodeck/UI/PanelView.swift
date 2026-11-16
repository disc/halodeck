import HalodeckCore
import SwiftUI

/// The menu-bar panel. What each side and corner does is set in Settings → Bindings.
struct PanelView: View {
    @ObservedObject var store: SettingsStore
    let engine: Engine
    var updates: UpdateService = .shared
    /// Closes the panel (before Sparkle's window takes over).
    var dismiss: () -> Void = {}
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
                Text("Halodeck").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Halodeck", isOn: $store.settings.enabled).labelsHidden()
            }
            .padding(.horizontal, 4)

            TrackpadMapView(settings: store.settings, brightnessAvailable: engine.brightnessAvailable, size: .compact)
                .frame(width: 236, height: 141)   // fixed: the popover can't size a Canvas by itself
                .frame(maxWidth: .infinity)

            if engine.state == .needsAccessibility {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Accessibility needed").font(.callout)
                    Spacer()
                    Button("Grant…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 4)
            }

            if let version = updates.availableVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                    Text("\(version) is available").font(.callout).lineLimit(1)
                    Spacer()
                    Button("Update…") {
                        dismiss()
                        updates.checkForUpdates()
                    }
                        .controlSize(.small)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Button { openSettings() } label: { Label("Settings…", systemImage: "gearshape") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(PanelButtonStyle())
        }
        .font(.system(size: 13))
        .toggleStyle(GlowSwitchStyle(compact: true))
        .tint(Theme.accent)
        .padding(12)
        .frame(width: 264)
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06)))
            .foregroundStyle(.primary)
    }
}
